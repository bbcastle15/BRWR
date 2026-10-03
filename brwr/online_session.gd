extends Node

signal status_changed(message: String)
signal lobby_changed
signal match_started
const BoardProjection = preload("res://network_projection.gd")
const Invite = preload("res://online_invite.gd")
const PORT := 27847
const PROTOCOL := "brwr-pvp-2"
var game = null
var room_code := ""
var started := false
var connected := false
var hosting := false
var busy := false
var version := ""
var player_count := 2
var local_player := 0
var seats: Array[int] = [0]
# These maps associate transport peers with seats, not a second gameplay state.
var peer_players: Dictionary = {}
var receiving: Dictionary = {}
var awaiting_auth: Dictionary = {}
var connection_started := 0
var state_sequence := 0
var received_sequence := -1

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_disconnected)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.allow_object_decoding = false
	# Text script exports produce the same fingerprint on Windows and Web.
	var hashes := PackedStringArray([PROTOCOL])
	for file in ["game.gd", "effect_resolver.gd", "room_effect_resolver.gd", "event_effect_resolver.gd", "quest_manager.gd", "network_projection.gd", "online_session.gd", "data/spells.json", "data/rooms.json", "data/events.json", "data/quests.json"]:
		hashes.append(FileAccess.get_sha256("res://" + file))
	if FileAccess.file_exists("res://web_build.json"):
		hashes.append(FileAccess.get_file_as_string("res://web_build.json"))
	version = "|".join(hashes).sha256_text()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if hosting:
		for id in awaiting_auth.keys():
			if now - int(awaiting_auth[id]) > 10000:
				multiplayer.multiplayer_peer.disconnect_peer(id)
				awaiting_auth.erase(id)
	elif connection_started > 0 and not connected and now - connection_started > 30000:
		_connection_failed()

func _make_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 4 * 1024 * 1024
	peer.outbound_buffer_size = 4 * 1024 * 1024
	peer.max_queued_packets = 64
	peer.handshake_timeout = 10.0
	return peer

func host(count: int = 2, bind_address: String = "*") -> Error:
	if OS.has_feature("web") or hosting or connected: return ERR_UNAVAILABLE
	if count < 2 or count > 6: return ERR_INVALID_PARAMETER
	var peer := _make_peer()
	var error := peer.create_server(PORT, bind_address)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	hosting = true
	connected = true
	player_count = count
	room_code = Crypto.new().generate_random_bytes(16).hex_encode()
	_update_lobby()
	return OK

func join(address: String, code: String) -> Error:
	if hosting or connected: return ERR_ALREADY_IN_USE
	room_code = code.strip_edges()
	var endpoint := Invite.websocket_address(address)
	if endpoint.is_empty() or room_code.is_empty(): return ERR_INVALID_PARAMETER
	var peer := _make_peer()
	var error := peer.create_client(endpoint)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		connection_started = Time.get_ticks_msec()
		status_changed.emit("Connessione in corso…")
	return error

func _peer_connected(id: int) -> void:
	if not hosting: return
	if started or awaiting_auth.size() >= 8:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	awaiting_auth[id] = Time.get_ticks_msec()

func _connected() -> void:
	_authenticate.rpc_id(1, room_code, version)

@rpc("any_peer", "call_remote", "reliable")
func _authenticate(code: String, client_version: String) -> void:
	if not hosting: return
	var sender := multiplayer.get_remote_sender_id()
	if peer_players.has(sender): return
	var reason := ""
	if started or peer_players.size() >= player_count - 1:
		reason = "Sala completa o partita già iniziata."
	elif code != room_code:
		reason = "Invito non valido. Chiedi all'host il link della sala corrente."
	elif client_version != version:
		reason = "Versioni diverse: ricarica il link. L'host deve ricreare la versione browser dopo le modifiche."
	if not reason.is_empty():
		_rejected.rpc_id(sender, reason)
		awaiting_auth[sender] = Time.get_ticks_msec() - 9500
		return
	for index in range(1, player_count):
		if not peer_players.values().has(index):
			peer_players[sender] = index
			break
	awaiting_auth.erase(sender)
	_update_lobby()

func _update_lobby() -> void:
	seats.assign([0])
	seats.append_array(peer_players.values())
	seats.sort()
	for id in peer_players:
		_lobby.rpc_id(id, player_count, peer_players[id], seats)
	lobby_changed.emit()
	status_changed.emit("Sala: %d/%d giocatori. Avvia quando sono tutti collegati." % [seats.size(), player_count])

@rpc("authority", "call_remote", "reliable")
func _lobby(count: int, seat: int, joined: Array) -> void:
	player_count = count
	local_player = seat
	seats.assign(joined)
	connected = true
	connection_started = 0
	lobby_changed.emit()
	status_changed.emit("Sei Player %d · %d/%d collegati · In attesa dell'host." % [seat + 1, seats.size(), count])

func can_start() -> bool:
	return hosting and connected and not started and peer_players.size() == player_count - 1

func start_match() -> bool:
	if not can_start(): return false
	started = true
	for id in peer_players:
		_begin.rpc_id(id, player_count, peer_players[id])
	_create_game.call_deferred(false)
	return true

@rpc("authority", "call_remote", "reliable")
func _rejected(message: String) -> void:
	connection_started = 0
	connected = false
	multiplayer.multiplayer_peer = null
	status_changed.emit(message)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _begin(count: int, seat: int) -> void:
	if started: return
	connected = true
	started = true
	player_count = count
	local_player = seat
	await _create_game(true)
	if not connected: return
	_ready_for_state.rpc_id(1)
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
	if not connected: return
	if not client:
		game.player_input_requested.connect(func(_request): call_deferred("publish"))
		game.game_over.connect(func(_result): call_deferred("publish"))
		game.start_game_flow()
		publish()
		match_started.emit()

@rpc("any_peer", "call_remote", "reliable")
func _ready_for_state() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if hosting and started and peer_players.has(sender):
		receiving[sender] = true
		publish()

func publish() -> void:
	if not hosting or not connected or game == null or game.beta_hud == null: return
	state_sequence += 1
	for id in receiving:
		var state: Dictionary = BoardProjection.build(game, int(peer_players[id]))
		state["sequence"] = state_sequence
		_snapshot.rpc_id(id, state)

@rpc("authority", "call_remote", "reliable")
func _snapshot(state: Dictionary) -> void:
	if game == null or not game.network_client: return
	var sequence := int(state.get("sequence", -1))
	if sequence <= received_sequence: return
	received_sequence = sequence
	busy = false
	BoardProjection.apply(game, state)

func submit_local(player: int, payload: Dictionary) -> bool:
	if not connected or busy or game == null or player != game.local_viewer_index: return false
	if player != int(game.pending_input.get("player_index", -1)): return false
	if game.network_client:
		busy = true
		_choose.rpc_id(1, game.input_revision, payload)
		return true
	var accepted: bool = game._submit_beta_input_authoritative(local_player, payload)
	publish()
	return accepted

@rpc("any_peer", "call_remote", "reliable")
func _choose(revision: int, payload: Dictionary) -> void:
	if not hosting or not connected or game == null: return
	var sender := multiplayer.get_remote_sender_id()
	if not peer_players.has(sender) or not receiving.has(sender): return
	var actor: int = peer_players[sender]
	var accepted := false
	if revision == game.input_revision and int(game.pending_input.get("player_index", -1)) == actor:
		accepted = game._submit_beta_input_authoritative(actor, payload)
	publish()
	if not accepted: _choice_rejected.rpc_id(sender)

@rpc("authority", "call_remote", "reliable")
func _choice_rejected() -> void:
	busy = false
	if game != null and game.beta_hud != null:
		game.beta_hud.present_pending_request(game.pending_input)
		game.beta_hud.feedback_label.text = "Scelta non valida o superata. Seleziona di nuovo."

func _connection_failed() -> void:
	connection_started = 0
	connected = false
	multiplayer.multiplayer_peer = null
	status_changed.emit("Connessione fallita: verifica link, host aperto e porta TCP %d nel router/firewall." % PORT)
	lobby_changed.emit()

func _peer_left(id: int) -> void:
	awaiting_auth.erase(id)
	if not hosting or not peer_players.has(id): return
	peer_players.erase(id)
	receiving.erase(id)
	if started:
		_disconnected()
		for remaining in peer_players:
			_match_paused.rpc_id(remaining)
	else:
		_update_lobby()

@rpc("authority", "call_remote", "reliable")
func _match_paused() -> void:
	_disconnected()

func _disconnected() -> void:
	connection_started = 0
	connected = false
	busy = true
	if game != null:
		game.clear_player_input()
		game._close_player_board_spell_preview()
		game._close_reference_card_preview()
		if game.beta_hud != null: game.beta_hud.hand_overlay.close_overlay(true)
	status_changed.emit("Connessione interrotta. Partita sospesa: torna al menu per iniziarne una nuova.")
	lobby_changed.emit()

func return_to_menu() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
