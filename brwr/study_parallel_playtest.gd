extends SceneTree

var failures := 0
var game

class FakeNetworkSession:
	extends Node
	func publish() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.player_count = 2
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8):
		await process_frame

	var fake_network := FakeNetworkSession.new()
	game.add_child(fake_network)
	game.network_session = fake_network
	game.network_client = false
	game.local_viewer_index = 0
	game.current_phase = game.PHASE_STUDY
	game.current_phase_play_order.assign([0, 1])
	game.waiting_for_player_input = false
	game.pending_input.clear()

	var initial_hand_sizes := [game.players[0].hand.size(), game.players[1].hand.size()]
	var ids := ["azoth_bomb", "deflagrate", "marbling", "stone_phoenix"]
	for player_index in [0, 1]:
		var drawn: Array = []
		for id in ids:
			drawn.append(game.clone_spell_card(game.spell_database.get_spell(id)))
		game.study_parallel_drawn_cards[player_index] = drawn

	check(game._begin_parallel_study_post_draw(), "Parallel post-draw Study starts")
	check(game.study_parallel_active, "Parallel Study state is active")
	check(game.get_beta_pending_input(0).get("type") == "study_keep_cards", "P1 gets private keep request")
	check(game.get_beta_pending_input(1).get("type") == "study_keep_cards", "P2 gets private keep request")

	# Player 2 can answer while Player 1 is still on the same Study step.
	check(game._submit_beta_input_authoritative(1, {"keep_indices": [0, 1], "_request_type": "study_keep_cards"}), "P2 keep accepted independently")
	check(game.get_beta_pending_input(1).get("type") == "study_optional_discard", "P2 advances to optional discard")
	check(
		not game._submit_beta_input_authoritative(1, {"keep_indices": [2, 3], "_request_type": "study_keep_cards"}),
		"A delayed Keep packet cannot skip P2's new Study step"
	)
	check(game.get_beta_pending_input(1).get("type") == "study_optional_discard", "P2 remains on the current private step after stale input")
	check(game.get_beta_pending_input(0).get("type") == "study_keep_cards", "P1 remains on keep step")

	check(game._submit_beta_input_authoritative(0, {"keep_indices": [0, 1], "_request_type": "study_keep_cards"}), "P1 keep accepted")
	check(game._submit_beta_input_authoritative(1, {"hand_index": -1, "_request_type": "study_optional_discard"}), "P2 completes Study first")
	check(game.study_parallel_active, "Phase waits for remaining player")
	check(bool(game.get_beta_pending_input(1).get("private", false)), "Completed P2 sees only waiting state")
	check(game._submit_beta_input_authoritative(0, {"hand_index": -1, "_request_type": "study_optional_discard"}), "P1 completes Study")
	check(not game.study_parallel_active and not game.waiting_for_player_input, "Study advances only after everybody finishes")
	check(
		game.players[0].hand.size() == initial_hand_sizes[0] + 2
		and game.players[1].hand.size() == initial_hand_sizes[1] + 2,
		"Each player kept exactly two cards"
	)

	print("STUDY PARALLEL: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
