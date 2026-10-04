extends SceneTree

# Exercise the same serialized, per-viewer snapshots used by OnlineSession.
# No relay service or external network is required for this presentation check.
class SnapshotLink extends Node:
	var host_game
	var client_game
	var packets: Array[Dictionary] = []
	func publish() -> void:
		var snapshot: Dictionary = load("res://network_projection.gd").build(host_game, 1)
		var decoded: Dictionary = bytes_to_var(var_to_bytes(snapshot))
		packets.append(decoded)
		load("res://network_projection.gd").apply(client_game, decoded)

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(8): await process_frame

func make_game(client: bool):
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.beta_force_fullscreen = false
	game.network_client = client
	game.local_viewer_index = 1 if client else 0
	game.game_seed = 1232
	root.add_child(game)
	await settle()
	game.table_shell = load("res://tabletop_shell.gd").new()
	game.add_child(game.table_shell)
	game.table_shell.setup(game)
	return game

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Presentation network test timed out"); quit(1))
	var host_game = await make_game(false)
	var client_game = await make_game(true)
	var link := SnapshotLink.new()
	link.host_game = host_game
	link.client_game = client_game
	root.add_child(link)
	host_game.network_session = link
	host_game.current_phase = host_game.PHASE_ACTION
	host_game.current_round = 1
	host_game.players[0].hand.append(host_game.spell_database.get_spell("heart_of_ice"))
	host_game._set_player_board_spell_slot(0, "I", host_game.players[0].hand[0], false, "prepared")
	host_game.summon_evocation(0, "nigredo", "forge")
	link.publish()
	host_game.queue_resolution({"type": "action_events", "context": {"game": host_game, "play_order": [0, 1]},
		"events": [host_game.event_database.get_event("black_thorns"), host_game.event_database.get_event("immortals")]})
	await settle()
	check(client_game.table_shell.card_overlay.visible and client_game.card_presentation.id == "black_thorns", "Client displays the first Event before resolution")
	check(client_game.players[0].evocations[0].damage_cubes.is_empty(), "Client has no premature Event damage")
	check(not client_game.get_player_board_spell_slot_data(0, "I").has("id") and client_game.players[0].hand[0] == null, "Public card animation preserves opponent privacy")
	await create_timer(host_game.CARD_PRESENTATION_SECONDS + 0.1).timeout
	check(client_game.card_presentation.get("id") == "immortals", "Sequential Events each receive their own overlay")
	check(client_game.players[0].evocations[0].damage_cubes.size() == 2, "First Event resolves before the second Event begins")
	await create_timer(host_game.CARD_PRESENTATION_SECONDS + 0.1).timeout
	check(client_game.players[0].evocations[0].damage_cubes.is_empty(), "Second Event heals only after its own presentation")
	check(not client_game.table_shell.card_overlay.visible and host_game.resolution_stack.is_empty(), "Both views leave the presentation without client acknowledgements")
	check(link.packets.size() >= 4, "Presentation and completion publish fresh snapshots")
	host_game.queue_free()
	client_game.queue_free()
	link.queue_free()
	await process_frame
	print("TABLETOP PRESENTATION NETWORK: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(failures)
