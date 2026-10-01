extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func exit_token(game, player_index: int) -> String:
	for option in game.pending_input.get("options", []):
		var action: Dictionary = option.get("action", {})
		if action.get("type") == "explore" and not action.get("activate_room_before_movement", false) and not action.get("activate_room_after_movement", false):
			return str(option.token)
	return ""
func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8):
		await process_frame
	var player = game.players[0]
	player.mage.speed = 2
	player.mage.in_cell = false
	player.mage.room_id = "forge"
	player.mage.room_coord = game.room_id_to_coord("forge")
	game.deal_damage(1, 0, 99, "spell")
	check(player.mage.in_cell and player.mage.get_damage() == 0, "Defeat must return healed Mage to Cell")
	game.current_phase = game.PHASE_ACTION
	game.current_phase_play_order.assign([0, 1])
	check(game._start_stepwise_action_activation(0), "Start post-defeat activation")
	var physical_before: int = player.available_physical_actions
	var token := exit_token(game, 0)
	check(token != "" and game.submit_action_activation_step(0, token), "Submit Cell exit")
	check(not player.mage.in_cell, "First Explore after idle defeat must leave Cell")
	check(player.available_physical_actions == physical_before - 1, "Successful exit must exhaust exactly one physical token")
	check(game.action_activation_actions_used == 1, "Successful exit must use exactly one activation slot")
	game.clear_player_input()
	game._reset_stepwise_action_activation()
	# Simulate damage interrupting an Explore after its token was committed.
	player.mage.in_cell = false
	player.mage.room_id = "forge"
	player.mage.room_coord = game.room_id_to_coord("forge")
	player.refresh_physical_actions()
	player.exhaust_physical_action()
	game.processing_resolution_stack = true
	game.queue_resolution({"type": "explore", "step": "move", "player_index": 0,
		"destination_room_ids": [game.player_entrance_room_ids[0]], "move_index": 0})
	game.deal_damage(1, 0, 99, "spell")
	game.processing_resolution_stack = false
	game.process_resolution_stack()
	check(player.mage.in_cell, "Defeat must still interrupt an ongoing physical action")
	check(player.available_physical_actions == 1, "Interrupted committed action must retain its token cost")
	check(game.resolution_stack.is_empty(), "Interrupted action must unwind")
	check(game._start_stepwise_action_activation(0), "A later activation must start normally")
	token = exit_token(game, 0)
	check(token != "" and game.submit_action_activation_step(0, token), "Leave Cell after interrupted action")
	check(not player.mage.in_cell and player.available_physical_actions == 0, "Cancellation must not affect the next physical action")
	print("CELL EXIT PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
