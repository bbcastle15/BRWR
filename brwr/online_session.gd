extends Node

signal status_changed(message: String)
signal lobby_changed
signal match_started

const BoardProjection = preload("res://network_projection.gd")
const Invite = preload("res://online_invite.gd")
const PROTOCOL := "brwr-relay-1"
const CONNECT_TIMEOUT_MS := 120000
const KEEPALIVE_MS := 30000

var game = null
var room_code := ""
var started := false
var connected := false
var hosting := false
var busy := false
var version := ""
var player_count := 2
var local_player := 0
var seats: Array[int] = []

# Host-side map: relay peer id -> BRWR player seat.
var peer_players: Dictionary = {}
var receiving: Dictionary = {}

var connection_started := 0
var state_sequence := 0
var received_sequence := -1

var _socket: WebSocketPeer = null
var _connect_mode := "" # "host" or "join"
var _pending_join_code := ""
var _hello_sent := false
var _last_keepalive := 0
var _closing_transport := false

func _ready() -> void:
	# Text-script exports produce the same fingerprint on Windows and Web.
	# Do not hash web_build.json: the relay only needs host and browser rules/data
	# to match, not a machine-local build metadata file.
	var hashes := PackedStringArray([PROTOCOL])
	for file in [
		"game.gd",
		"effect_resolver.gd",
		"death_effect_resolver.gd",
		"triggered_spell_manager.gd",
		"room_effect_resolver.gd",
		"event_effect_resolver.gd",
		"quest_manager.gd",
		"network_projection.gd",
		"online_session.gd",
		"data/spells.json",
		"data/mages.json",
		"data/school_specializations_v19.json",
		"data/rooms.json",
		"data/events.json",
		"data/quests.json",
	]:
		hashes.append(FileAccess.get_sha256("res://" + file))
	version = "|".join(hashes).sha256_text()

func _process(_delta: float) -> void:
	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()
	var now := Time.get_ticks_msec()

	if state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_send_hello()

		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var text := packet.get_string_from_utf8()
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				_handle_relay_message(parsed)

		if now - _last_keepalive >= KEEPALIVE_MS:
			_send_json({"type": "ping"})
			_last_keepalive = now

	elif state == WebSocketPeer.STATE_CLOSED:
		if _closing_transport:
			_socket = null
			return
		_transport_lost()

	if connection_started > 0 and not connected and now - connection_started > CONNECT_TIMEOUT_MS:
		_connection_failed("Timeout di connessione al server online.")

# Signature intentionally stays compatible with the previous local-host version.
# bind/TLS arguments are ignored: the host now opens an outbound WSS connection.
func host(count: int = 2, _bind_address: String = "*", _tls_server_options = null) -> Error:
	if hosting or connected or connection_started > 0:
		return ERR_ALREADY_IN_USE
	if count < 2 or count > 6:
		return ERR_INVALID_PARAMETER

	var endpoint := Invite.websocket_address()
	if endpoint.is_empty():
		status_changed.emit("Server online non configurato. Imposta online_server_url.txt con l'URL Render.")
		return ERR_INVALID_PARAMETER

	player_count = count
	local_player = 0
	room_code = ""
	seats.clear()
	peer_players.clear()
	receiving.clear()
	started = false
	busy = false
	return _connect_relay(endpoint, "host", "")

func join(address: String, code: String) -> Error:
	if hosting or connected or connection_started > 0:
		return ERR_ALREADY_IN_USE

	var endpoint := Invite.websocket_address(address)
	var clean_code := code.strip_edges()
	if endpoint.is_empty() or clean_code.is_empty():
		return ERR_INVALID_PARAMETER

	room_code = clean_code
	_pending_join_code = clean_code
	seats.clear()
	peer_players.clear()
	receiving.clear()
	started = false
	busy = false
	return _connect_relay(endpoint, "join", clean_code)

func _connect_relay(endpoint: String, mode: String, code: String) -> Error:
	_close_transport()
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 4 * 1024 * 1024
	_socket.outbound_buffer_size = 4 * 1024 * 1024
	_socket.max_queued_packets = 64

	var error := _socket.connect_to_url(endpoint)
	if error != OK:
		_socket = null
		return error

	_connect_mode = mode
	_pending_join_code = code
	_hello_sent = false
	_closing_transport = false
	connection_started = Time.get_ticks_msec()
	_last_keepalive = connection_started
	status_changed.emit("Connessione al server online in corso…")
	lobby_changed.emit()
	return OK

func _send_hello() -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var message := {
		"type": "create" if _connect_mode == "host" else "join",
		"protocol": PROTOCOL,
		"version": version,
	}
	if _connect_mode == "host":
		message["count"] = player_count
	else:
		message["code"] = _pending_join_code

	if _send_json(message) == OK:
		_hello_sent = true

func _send_json(message: Dictionary) -> Error:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return _socket.send_text(JSON.stringify(message))

func _handle_relay_message(message: Dictionary) -> void:
	var kind := str(message.get("type", ""))
	match kind:
		"created":
			if _connect_mode != "host":
				return
			room_code = str(message.get("code", ""))
			player_count = int(message.get("count", player_count))
			local_player = 0
			seats.assign([0])
			hosting = true
			connected = true
			connection_started = 0
			status_changed.emit("Sala creata sul server online · 1/%d giocatori." % player_count)
			lobby_changed.emit()

		"joined":
			if _connect_mode != "join":
				return
			player_count = int(message.get("count", 2))
			local_player = int(message.get("seat", 1))
			seats.clear()
			for seat in message.get("seats", []):
				seats.append(int(seat))
			connected = true
			hosting = false
			connection_started = 0
			status_changed.emit("Sei Player %d · In attesa dell'host." % [local_player + 1])
			lobby_changed.emit()

		"peer_joined":
			if not hosting:
				return
			var peer_id := str(message.get("peer_id", ""))
			var seat := int(message.get("seat", -1))
			if not peer_id.is_empty() and seat >= 1 and seat < player_count:
				peer_players[peer_id] = seat
				_update_lobby()

		"peer_left":
			if not hosting:
				return
			_peer_left(str(message.get("peer_id", "")))

		"game":
			var encoded := str(message.get("payload", ""))
			if encoded.is_empty():
				return
			var payload = Marshalls.base64_to_variant(encoded, false)
			if payload is Dictionary:
				_handle_game_message(str(message.get("peer_id", "")), payload)

		"room_closed":
			_disconnected("La sala è stata chiusa dall'host.")

		"error":
			_connection_failed(str(message.get("message", "Errore del server online.")))

		"pong":
			pass

func _handle_game_message(peer_id: String, payload: Dictionary) -> void:
	var op := str(payload.get("op", ""))
	if hosting:
		match op:
			"ready":
				_ready_for_state(peer_id)
			"choose":
				_choose(peer_id, int(payload.get("revision", -1)), payload.get("payload", {}))
		return

	match op:
		"lobby":
			_lobby(int(payload.get("count", 2)), int(payload.get("seat", local_player)), payload.get("joined", []))
		"begin":
			_begin(int(payload.get("count", 2)), int(payload.get("seat", local_player)))
		"snapshot":
			_snapshot(payload.get("state", {}))
		"choice_rejected":
			_choice_rejected()
		"match_paused":
			_disconnected("Connessione interrotta. Partita sospesa: torna al menu per iniziarne una nuova.")

func _send_game_to_peer(peer_id: String, payload: Dictionary) -> Error:
	if not hosting or peer_id.is_empty():
		return ERR_INVALID_PARAMETER
	return _send_json({
		"type": "game",
		"to": peer_id,
		"payload": Marshalls.variant_to_base64(payload, false),
	})

func _send_game_to_host(payload: Dictionary) -> Error:
	if hosting:
		return ERR_INVALID_PARAMETER
	return _send_json({
		"type": "game",
		"payload": Marshalls.variant_to_base64(payload, false),
	})

func _update_lobby() -> void:
	seats.assign([0])
	seats.append_array(peer_players.values())
	seats.sort()
	for id in peer_players:
		_send_game_to_peer(str(id), {
			"op": "lobby",
			"count": player_count,
			"seat": int(peer_players[id]),
			"joined": seats,
		})
	lobby_changed.emit()
	status_changed.emit("Sala: %d/%d giocatori. Avvia quando sono tutti collegati." % [seats.size(), player_count])

func _lobby(count: int, seat: int, joined: Array) -> void:
	player_count = count
	local_player = seat
	seats.clear()
	for value in joined:
		seats.append(int(value))
	connected = true
	connection_started = 0
	lobby_changed.emit()
	status_changed.emit("Sei Player %d · %d/%d collegati · In attesa dell'host." % [seat + 1, seats.size(), count])

func can_start() -> bool:
	return hosting and connected and not started and peer_players.size() == player_count - 1

func start_match() -> bool:
	if not can_start():
		return false
	started = true
	_send_json({"type": "lock"})
	for id in peer_players:
		_send_game_to_peer(str(id), {
			"op": "begin",
			"count": player_count,
			"seat": int(peer_players[id]),
		})
	_create_game.call_deferred(false)
	return true

func _begin(count: int, seat: int) -> void:
	if started:
		return
	connected = true
	started = true
	player_count = count
	local_player = seat
	await _create_game(true)
	if not connected:
		return
	_send_game_to_host({"op": "ready"})
	match_started.emit()

func _create_game(client: bool) -> void:
	game = load("res://game.tscn").instantiate()
	game.name = "Game"
	game.network_session = self
	game.network_client = client
	game.local_viewer_index = local_player
	game.player_count = player_count
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	add_child(game)

	# Game._ready awaits layout; wait for its actual UI instead of N frames.
	while game.beta_hud == null and connected:
		await get_tree().process_frame
	if not connected:
		return

	if not client:
		game.player_input_requested.connect(func(_request): call_deferred("publish"))
		game.game_over.connect(func(_result): call_deferred("publish"))
		game.start_game_flow()
		publish()
		match_started.emit()

func _ready_for_state(peer_id: String) -> void:
	if hosting and started and peer_players.has(peer_id):
		receiving[peer_id] = true
		publish()

func publish() -> void:
	if not hosting or not connected or game == null or game.beta_hud == null:
		return
	state_sequence += 1
	for id in receiving:
		var state: Dictionary = BoardProjection.build(game, int(peer_players[id]))
		state["sequence"] = state_sequence
		_send_game_to_peer(str(id), {"op": "snapshot", "state": state})

func _snapshot(state: Dictionary) -> void:
	if game == null or not game.network_client:
		return
	var sequence := int(state.get("sequence", -1))
	if sequence <= received_sequence:
		return
	received_sequence = sequence
	busy = false
	BoardProjection.apply(game, state)

func submit_local(player: int, payload: Dictionary) -> bool:
	if not connected or busy or game == null or player != game.local_viewer_index:
		return false
	var active_request: Dictionary = game.get_beta_pending_input(player)
	if bool(active_request.get("private", false)) \
	or player != int(active_request.get("player_index", -1)):
		return false

	var submitted_payload: Dictionary = payload.duplicate(true)
	if str(active_request.get("type", "")) in [
		"study_keep_cards",
		"study_optional_discard",
		"study_hand_limit"
	]:
		submitted_payload["_request_type"] = str(active_request.get("type", ""))

	if game.network_client:
		busy = true
		var error := _send_game_to_host({
			"op": "choose",
			"revision": game.input_revision,
			"payload": submitted_payload,
		})
		if error != OK:
			busy = false
			return false
		return true

	var accepted: bool = game._submit_beta_input_authoritative(local_player, submitted_payload)
	publish()
	return accepted

func _choose(peer_id: String, revision: int, payload: Dictionary) -> void:
	if not hosting or not connected or game == null:
		return
	if not peer_players.has(peer_id) or not receiving.has(peer_id):
		return

	var actor: int = int(peer_players[peer_id])
	var accepted := false
	var active_request: Dictionary = game.get_beta_pending_input(actor)
	if revision == game.input_revision \
	and not bool(active_request.get("private", false)) \
	and int(active_request.get("player_index", -1)) == actor:
		accepted = game._submit_beta_input_authoritative(actor, payload)
	publish()
	if not accepted:
		_send_game_to_peer(peer_id, {"op": "choice_rejected"})

func _choice_rejected() -> void:
	busy = false
	if game != null and game.beta_hud != null:
		game.beta_hud.present_pending_request(game.pending_input)
		game.beta_hud.feedback_label.text = "Scelta non valida o superata. Seleziona di nuovo."

func _peer_left(peer_id: String) -> void:
	if peer_id.is_empty() or not peer_players.has(peer_id):
		return
	peer_players.erase(peer_id)
	receiving.erase(peer_id)
	if started:
		connected = false
		busy = true
		for remaining in peer_players:
			_send_game_to_peer(str(remaining), {"op": "match_paused"})
		_disconnected("Un giocatore si è disconnesso. Partita sospesa: torna al menu per iniziarne una nuova.")
	else:
		_update_lobby()

func _connection_failed(message: String = "") -> void:
	var reason := message
	if reason.is_empty():
		reason = "Connessione fallita: verifica il server online e riprova."
	_close_transport()
	connection_started = 0
	connected = false
	hosting = false
	busy = false
	status_changed.emit(reason)
	lobby_changed.emit()

func _transport_lost() -> void:
	var was_active := connected or hosting or started
	_socket = null
	connection_started = 0
	if was_active:
		_disconnected("Connessione al server online interrotta. Partita sospesa.")
	else:
		_connection_failed()

func _disconnected(message: String = "Connessione interrotta. Partita sospesa: torna al menu per iniziarne una nuova.") -> void:
	connection_started = 0
	connected = false
	busy = true
	if game != null:
		game.clear_player_input()
		game._close_player_board_spell_preview()
		game._close_reference_card_preview()
		if game.beta_hud != null:
			game.beta_hud.hand_overlay.close_overlay(true)
	status_changed.emit(message)
	lobby_changed.emit()

func _close_transport() -> void:
	if _socket == null:
		return
	_closing_transport = true
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close(1000, "BRWR session closed")
	_socket = null

func return_to_menu() -> void:
	_close_transport()
	get_tree().reload_current_scene()
