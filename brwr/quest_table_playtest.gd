extends SceneTree

var failures := 0
var destination_chosen := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	await process_frame
	var player = game.players[0]
	player.active_quests.clear()
	player.completed_quests.clear()
	var card := QuestCardState.new("shattered_illusion", "Shattered Illusion", 1, {"trigger": "test_progress"}, [], 2, 1)
	game.quest_decks[1] = [card, card, card, card]
	game.current_moon = 1
	var manager = game.quest_manager
	var quest = manager.draw_phase_quest(game, 0)
	check(quest != null, "Empty active slot must draw")
	var remaining: int = game.quest_decks[1].size()
	check(manager.draw_phase_quest(game, 0) == null, "Hidden Quest must prevent phase draw")
	quest.reveal()
	check(manager.draw_phase_quest(game, 0) == null, "Revealed Quest must prevent phase draw")
	check(game.quest_decks[1].size() == remaining, "Blocked draw must not consume deck")
	check(manager.draw_quest(game, 0) != null, "Effect draws remain legal with an active Quest")
	manager.process_event(game, {"player_index": 0, "type": "test_progress"})
	var board = game.player_boards[0]
	var progress = board.get_node("Quest_revealed").get_child(0).get_child(0).get_node("QuestProgress")
	check(progress.get_child_count() == 2, "Quest must show two cube slots")
	check(progress.get_child(0).color == board.get_damage_cube_color(0), "Progress cube must use owner color immediately")
	check(progress.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "Cube must not block inspection")
	manager.process_event(game, {"player_index": 0, "type": "test_progress"})
	check(player.active_quests.is_empty(), "Completed Quests must leave active slot")
	check(manager.draw_phase_quest(game, 0) != null, "Completed Quest must not prevent phase draw")
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	player.hand.clear()
	game.local_viewer_index = 0
	hud._refresh_header()
	check(not hud.hand_button.disabled, "Empty spell hand must still allow private Quest inspection")
	hud.hand_button.pressed.emit()
	check(hud.hand_overlay.visible, "Hand button must open an empty hand")
	board.refresh()
	check(board.get_node("Quest_revealed").get_child(0).get_child_count() == 1, "Owner's hidden Quest must be on the left of the board")
	check(not board.get_node("Quest_revealed").get_child(0).get_child(0).disabled, "Owner can inspect hidden Quest from the board")
	hud.hand_overlay.close_overlay(true)
	check(hud.get_reserved_width() == 0, "No space reserved for right sidebar")
	check(hud.panel.anchor_top == 0.5 and hud.panel.anchor_left == 0.5, "Choices must be in centered overlay")
	var room_id: String = str(game.room_id_by_coord.values()[0])
	hud.current_request = {"type": "effect_choice", "choice_kind": "evocation_activation_plan", "min_select": 1, "max_select": 1, "options": [{"token": "plan:0", "path": [room_id], "label": "Move"}]}
	hud._render_current_request()
	check(get_nodes_in_group("lodge_room_choices").size() == 1, "Spell evocation movement must highlight destination")
	var camera = load("res://table_camera.gd").new()
	game.add_child(camera)
	await process_frame
	camera.force_update_scroll()
	var point := Vector2(630, 310)
	var before: Vector2 = camera.get_canvas_transform().affine_inverse() * point
	camera.zoom_at(point, 1.15)
	var after: Vector2 = camera.get_canvas_transform().affine_inverse() * point
	check(before.distance_to(after) < 0.1, "Zoom must preserve world point under pointer")
	hud._render_lodge_paths([{"path": [room_id], "callback": func(): destination_chosen = true}])
	await process_frame
	var destination = get_nodes_in_group("lodge_room_choices")[-1]
	var click_point: Vector2 = destination.get_global_transform_with_canvas() * (destination.size * 0.5)
	var hover := InputEventMouseMotion.new()
	hover.position = click_point
	root.push_input(hover, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = click_point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		root.push_input(click, true)
	check(destination_chosen, "Room remains clickable after camera zoom")
	var start_position: Vector2 = camera.position
	camera.dragging = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 20)
	camera._input(motion)
	check(camera.position != start_position, "Drag must move camera")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	camera._input(release)
	check(not camera.dragging, "Right release must stop dragging")
	camera.reset_view()
	check(camera.zoom.x > 0 and camera.position == game.get_tabletop_bounds().get_center(), "Reset view must fit the complete tabletop")
	print("QUEST TABLE PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
