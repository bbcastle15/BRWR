extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	check(game.game_seed == 0, "Normal startup must randomize the seed")
	game.game_seed = 1232
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	game.beta_hud = hud
	hud.setup(game)
	await process_frame
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.speed = 2
	player.mage.room_id = game.player_entrance_room_ids[0]
	var source = game.spell_database.spells["ineluctable_pain"]
	var copy := SpellCardState.new(source.id, source.card_name, source.school_id, source.light_side, source.dark_side)
	player.ready_spells.assign([ReadySpellState.new(source, true), ReadySpellState.new(copy, true)])
	game._set_player_board_spell_slot(0, "I", source, true, "prepared")
	game._set_player_board_spell_slot(0, "II", copy, true, "prepared")
	game.current_phase = game.PHASE_ACTION
	game._start_stepwise_action_activation(0)
	await process_frame
	var board = game.player_boards[0]
	check(not hud.panel.visible, "Action root must leave tabletop unobstructed")
	check(not board.get_node("PhysicalAction0").disabled, "Owner token must allow legal actions")
	check(game.player_boards[1].get_node("PhysicalAction0").disabled, "Other player's tokens cannot be used")
	check(game.get_player_board_cast_token(0, "I") != "", "Lowest prepared slot must cast")
	check(game.get_player_board_cast_token(0, "II") == "", "Duplicate card ID must not let later physical instance cast")
	game.open_player_board_action(0, "physical")
	check(hud.panel.visible and hud.action_menu_mode == "physical", "Token opens physical choices")
	var labels: Array = []
	for child in hud.content.get_children():
		if child is Button and not child.is_queued_for_deletion():
			labels.append(child.text)
	check(labels.has("Explore"), "Physical menu must contain Explore: " + str(labels))
	check(not labels.any(func(label): return str(label).begins_with("Cast")), "Physical menu must not contain spell commands")
	hud._toggle_panel()
	check(not hud.panel.visible and game.waiting_for_player_input, "Hide preserves pending decision")
	hud._toggle_panel()
	game.activate_player_board_spell(0, "I", true)
	check(game.get_node("SpellCardPreview").root.visible, "Shift-inspection must preserve private preview")
	check(game.action_activation_actions_used == 0, "Inspect must not spend an action")
	game.activate_player_board_spell(0, "I")
	check(game.action_activation_actions_used == 1, "Board spell click commits one action")
	check(player.ready_spells.size() == 1 and player.ready_spells[0].spell == copy, "Cast removes only selected instance")
	check(game.get_player_board_spell_slot_data(0, "I").get("public", false), "Cast must reveal physical slot")
	check(game.get_player_board_cast_token(0, "II") == "", "Second numbered spell remains unavailable in same activation")
	check(not game.get_node("SpellCardPreview").root.visible, "Submitting action closes private inspection")
	var physical: Array = game.get_player_board_action_options(0, "physical")
	var explore: Dictionary = {}
	for option in physical:
		var action: Dictionary = option.get("action", {})
		if action.get("type") == "explore" and action.get("destination_room_ids", []).is_empty() \
		and not action.get("activate_room_before_movement", false) and not action.get("activate_room_after_movement", false):
			explore = option
			break
	check(not explore.is_empty(), "Fixture must offer a stationary Explore")
	if not explore.is_empty():
		hud._submit_action_token(explore.token)
	check(player.available_physical_actions == 1, "Physical choice must exhaust exactly one authoritative token")
	check(board.get_node("PhysicalAction1").text == "×", "Spent physical token must be visibly exhausted")
	game.clear_player_input()
	game.request_player_input({"player_index": 1, "type": "starting_school_choice", "schools": []})
	check(hud.panel.visible and hud.panel.anchor_top == 0.5, "Setup choices must open centered")
	check(board.get_node("PhysicalAction1").text == "×", "Token expenditure remains public during handoff")
	check(game.get_player_board_action_request(0).is_empty(), "Old owner cannot act after handoff")
	player.refresh_physical_actions()
	board.refresh()
	check(board.get_node("PhysicalAction1").text == "+", "Refreshed token must become visibly available")
	var camera = load("res://table_camera.gd").new()
	game.add_child(camera)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	camera._input(event)
	check(camera.dragging, "Right press must start panning before GUI handling")
	event.pressed = false
	camera._input(event)
	check(not camera.dragging, "Right release must stop panning")
	print("BOARD ACTIONS PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
