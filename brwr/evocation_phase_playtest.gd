extends SceneTree

# Godot --headless --path . --script res://evocation_phase_playtest.gd
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var first := EvocationState.new("copy", "First", "beast", 5, 1, 1, 0)
	var second := EvocationState.new("copy", "Second", "beast", 5, 1, 1, 0)
	var other := EvocationState.new("other", "Other", "beast", 5, 1, 1, 1)
	first.room_id = game.player_entrance_room_ids[0]
	second.room_id = first.room_id
	other.room_id = game.player_entrance_room_ids[1]
	game.players[0].evocations.assign([first, second])
	game.players[1].evocations.assign([other])
	game.current_phase = game.PHASE_EVOCATION
	game.current_phase_play_order.assign([0, 1])
	game.advance_evocation_phase()
	check(game.pending_input.get("required_count") == 1, "Phase must request one activation")
	check(game.pending_input.get("remaining_count") == 2, "Both unactivated instances must be selectable")
	check(not game.submit_evocation_phase_activations(0, [
		{"evocation_index": 0, "context": {}}, {"evocation_index": 1, "context": {}}
	]), "Bulk activation plans must be rejected")
	var movement: Dictionary = {}
	for plan in game.pending_input.evocations[0].activation_plans:
		if plan.get("attack_timing") == "none" and not plan.get("path", []).is_empty():
			movement = plan.context.duplicate(true)
			break
	check(not movement.is_empty(), "Fixture must offer a legal movement")
	var destination: String = str(movement.get("evocation_move_room_ids", [first.room_id])[-1])
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	# Simulate a paused resolution stack: no next selection may open early.
	game.processing_resolution_stack = true
	hud._choose_evocation_plan(0, movement)
	check(not game.waiting_for_player_input, "Next choice must wait for resolution")
	check(first.room_id != destination, "Queued movement must not execute before resolution resumes")
	game.processing_resolution_stack = false
	game.process_resolution_stack()
	check(first.room_id == destination, "First movement must finish before the second choice")
	check(game.pending_input.get("player_index") == 0, "Same player chooses their second activation")
	check(game.pending_input.get("remaining_count") == 1, "Activated instance must disappear from choices")
	check(game.pending_input.evocations[0].evocation_index == 1, "The other duplicate remains selectable")
	check(not game.submit_evocation_phase_activations(0, [{"evocation_index": 0, "context": {}}]), "An instance cannot activate twice")
	# Removal shifts indices; activation tracking must still follow references.
	game.players[0].evocations.erase(first)
	game.clear_player_input()
	game.advance_evocation_phase()
	check(game.pending_input.evocations[0].evocation_index == 0, "Remaining instance must survive array compaction")
	var no_action := {"evocation_attack_timing": "none", "evocation_move_room_ids": []}
	check(game.submit_evocation_phase_activations(0, [{"evocation_index": 0, "context": no_action}]), "Second activation must resolve immediately")
	check(game.pending_input.get("player_index") == 1, "Next player starts only after all current activations finish")
	check(game.submit_evocation_phase_activations(1, [{"evocation_index": 0, "context": no_action}]), "Last activation must resolve")
	check(not game.waiting_for_player_input and game.evocation_phase_activated.is_empty(), "Phase completion must reset activation tracking")
	print("EVOCATION PHASE PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
