extends Node

signal status_changed(message: String)
signal match_started
const BoardProjection = preload("res://network_projection.gd")
const PORT := 27847
const PROTOCOL := "brwr-pvp-1"
var game = null
var room_code := ""
var remote_peer := 0
var started := false
var connected := false
var busy := false
var receiving := false
var version := ""

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): status_changed.emit("Connessione fallita: verifica IP host, porta UDP 27847, codice e firewall."))
	multiplayer.server_disconnected.connect(_disconnected)
	multiplayer.peer_disconnected.connect(func(id):
		if id == remote_peer: _disconnected())
	# Reject incompatible rules/code before starting the match.
	var hashes := PackedStringArray([PROTOCOL])
	for file in ["game.gd", "effect_resolver.gd", "room_effect_resolver.gd", "network_projection.gd", "data/spells.json", "data/rooms.json", "data/events.json", "data/quests.json"]:
		hashes.append(FileAccess.get_sha256("res://" + file))
	version = "|".join(hashes).sha256_text()

func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 1)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	room_code = "%06d" % (randi() % 1000000)
	status_changed.emit("In attesa dell'amico · Codice: " + room_code + " · Porta UDP %d" % PORT)
	return OK

func join(address: String, code: String) -> Error:
	room_code = code.strip_edges()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		status_changed.emit("Connessione in corso…")
	return error

func _connected() -> void:
	_authenticate.rpc_id(1, room_code, version)

@rpc("any_peer", "call_remote", "reliable")
func _authenticate(code: String, client_version: String) -> void:
	if not multiplayer.is_server(): return
	var sender := multiplayer.get_remote_sender_id()
	if started or code != room_code or client_version != version:
		_rejected.rpc_id(sender, "Codice errato o versioni del progetto diverse.")
		return
	remote_peer = sender
	connected = true
	started = true
	_begin.rpc_id(sender)
	await _create_game(false)
	game.start_game_flow()
	match_started.emit()

@rpc("authority", "call_remote", "reliable")
func _rejected(message: String) -> void:
	status_changed.emit(message)

@rpc("authority", "call_remote", "reliable")
func _begin() -> void:
	connected = true
	started = true
	await _create_game(true)
	_ready_for_state.rpc_id(1)
	match_started.emit()

func _create_game(client: bool) -> void:
	game = load("res://game.tscn").instantiate()
	game.name = "Game"
	game.network_session = self
	game.network_client = client
	game.local_viewer_index = 1 if client else 0
	game.player_count = 2
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	add_child(game)
	for frame in range(8): await get_tree().process_frame
	if not client:
		game.player_input_requested.connect(func(_request): call_deferred("publish"))
		game.game_over.connect(func(_result): call_deferred("publish"))

@rpc("any_peer", "call_remote", "reliable")
func _ready_for_state() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == remote_peer:
		receiving = true
		publish()

func publish() -> void:
	if not connected or not receiving or game == null: return
	_snapshot.rpc_id(remote_peer, BoardProjection.build(game, 1))

@rpc("authority", "call_remote", "reliable")
func _snapshot(state: Dictionary) -> void:
	if game == null or not game.network_client: return
	busy = false
	BoardProjection.apply(game, state)

func submit_local(player: int, payload: Dictionary) -> bool:
	if not connected or busy or player != game.local_viewer_index: return false
	if player != int(game.pending_input.get("player_index", -1)): return false
	if game.network_client:
		busy = true
		_choose.rpc_id(1, game.input_revision, payload)
		return true
	var accepted: bool = game._submit_beta_input_authoritative(0, payload)
	publish()
	return accepted

@rpc("any_peer", "call_remote", "reliable")
func _choose(revision: int, payload: Dictionary) -> void:
	if not multiplayer.is_server() or not connected or game == null: return
	if multiplayer.get_remote_sender_id() != remote_peer: return
	var accepted := false
	if revision == game.input_revision and int(game.pending_input.get("player_index", -1)) == 1:
		accepted = game._submit_beta_input_authoritative(1, payload)
	publish()
	if not accepted: _choice_rejected.rpc_id(remote_peer)

@rpc("authority", "call_remote", "reliable")
func _choice_rejected() -> void:
	busy = false
	if game != null and game.beta_hud != null:
		game.beta_hud.present_pending_request(game.pending_input)
		game.beta_hud.feedback_label.text = "Scelta non valida o superata. Seleziona di nuovo."

func _disconnected() -> void:
	connected = false
	busy = true
	if game != null:
		game.clear_player_input()
		game._close_player_board_spell_preview()
		if game.beta_hud != null: game.beta_hud.hand_overlay.close_overlay(true)
	status_changed.emit("Connessione interrotta. Partita sospesa: torna al menu per iniziarne una nuova.")
