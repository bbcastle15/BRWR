extends SceneTree

var failures := 0
var selected_path: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func choose(path: Array) -> void:
	selected_path = path

func run() -> void:
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	var player = game.players[0]
	player.active_quests.clear()
	player.completed_quests.clear()
	var quest := QuestState.new(QuestCardState.new("test_quest", "Test Quest", 1, {"trigger": "spell_resolved"}, [{"type": "gain_power", "amount": 1}], 2, 1), 0)
	player.active_quests.append(quest)
	game.request_player_input({"player_index": 0, "type": "board_test"})
	check(game.get_player_quest_cards(0, "private").size() == 1, "Owner must see private Quest")
	var hand = load("res://hand_overlay.gd").new()
	game.add_child(hand)
	hand.setup(game)
	hand.open_browse(0)
	check(hand.private_quest_row.get_child_count() == 1, "Private Quests must be available in Hand")
	hand.close_overlay()
	game.open_quest_card(quest)
	var preview = game.get_node("ReferenceCardPreview")
	check(preview.root.visible, "Private Quest must open enlarged inspection")
	game.clear_player_input()
	game.request_player_input({"player_index": 1, "type": "board_test"})
	check(not preview.root.visible and game.get_player_quest_cards(0, "private").is_empty(), "Handoff must hide private Quest and close preview")
	game.open_quest_card(quest)
	check(not preview.root.visible, "Unauthorized direct inspect must fail")
	quest.revealed = true
	await process_frame
	check(game.get_player_quest_cards(0, "revealed").size() == 1, "Revealed Quest must appear on left")
	game.player_boards[0].get_node("Quest_revealed").get_child(0).get_child(0).pressed.emit()
	check(preview.root.visible, "Revealed Quest must be public")
	quest.completed = true
	player.active_quests.erase(quest)
	player.completed_quests.append(quest)
	await process_frame
	check(game.get_player_quest_cards(0, "completed").size() == 1 and game.get_player_quest_cards(0, "revealed").is_empty(), "Completed Quest must move to right")
	quest.solved = true
	await process_frame
	check(game.get_player_quest_cards(0, "completed").is_empty() and game.player_boards[0].get_node("SolvedQuestCount").text.ends_with("1"), "Solved Quest must leave cards and increment counter")
	game._close_reference_card_preview()
	var event := EventCardState.new("growth", "Growth", 1, false, "action", 1)
	game.active_events[0] = event
	game.get_node("EventBoard").refresh_event_slots()
	var event_views = game.get_node("EventBoard").find_children("EventView", "Button", true, false)
	check(not event_views.is_empty(), "EventBoard must contain clickable cards")
	var event_art = event_views[0].get_child(0)
	check(is_equal_approx(event_art.rotation, PI / 2.0), "Event art must rotate clockwise in the board slot")
	check(event_art.size.is_equal_approx(Vector2(52, 80)), "Rotated portrait must fit the 80x52 slot")
	for corner in [Vector2.ZERO, Vector2(52, 0), Vector2(0, 80), Vector2(52, 80)]:
		var mapped: Vector2 = event_art.get_transform() * corner
		check(mapped.x >= -0.01 and mapped.x <= 80.01 and mapped.y >= -0.01 and mapped.y <= 52.01, "Rotated art must stay inside clickable slot bounds")
	event_views[0].pressed.emit()
	check(preview.root.visible and preview.art.texture != null, "Event inspector must load actual event art")
	check(is_zero_approx(preview.art.rotation), "Event inspection must remain upright")
	game._close_reference_card_preview()
	var spell = game.spell_database.spells["ineluctable_pain"]
	game._set_player_board_spell_slot(0, "I", spell, true, "revealed")
	var active := ActiveSpellState.new(spell, 0, true)
	player.active_spells.append(active)
	check(game.get_player_board_spell_slot_data(0, "I").get("marker") == "PERMANENT", "Self ongoing spell must have Permanent on card")
	var room_id: String = game.player_entrance_room_ids[0]
	var room_spell := SpellCardState.new("test_room", "Room permanent", "alchemy", {"type": "contingency", "target": "room", "trigger": {"event": "move"}}, {})
	var room_active := ActiveSpellState.new(room_spell, 0, false)
	room_active.context["target_room_id"] = room_id
	player.active_spells.append(room_active)
	await process_frame
	check(game.get_room_by_id(room_id).get_node("PermanentMarkers").get_child_count() == 1, "Room ongoing effect must place Permanent in target room")
	room_active.active = false
	await process_frame
	check(game.get_room_by_id(room_id).get_node("PermanentMarkers").get_child_count() == 0, "Deactivated room effect must remove its token")
	var trap = game.spell_database.spells["liquefy_the_pain"]
	game._set_player_board_spell_slot(0, "II", trap, false, "armed")
	var armed := ActiveSpellState.new(trap, 0, false)
	player.active_spells.append(armed)
	var hidden_slot: Dictionary = game.get_player_board_spell_slot_data(0, "II")
	check(hidden_slot.get("marker", "") == "TRAP" and not hidden_slot.has("id") and not hidden_slot.get("can_inspect", false), "Armed marker is public but card identity and inspection remain private")
	game.clear_player_input()
	game.request_player_input({"player_index": 0, "type": "board_test"})
	check(game.get_player_board_spell_slot_data(0, "II").get("marker", "") in ["TRAP", "PROTECTION"], "Owner must see armed marker")
	# Click the actual hex overlay through the HUD; only legal next steps appear.
	for board in game.player_boards:
		board.hide()
	var first: String = game.player_entrance_room_ids[0]
	var next_rooms: Array = game._beta_adjacent_room_ids(first)
	var second: String = str(next_rooms[0])
	game.get_room_by_id(first).global_position = Vector2(400, 350)
	game.get_room_by_id(second).global_position = Vector2(700, 350)
	hud._render_lodge_paths([{"path": [first, second], "callback": choose.bind([first, second])}])
	await process_frame
	var overlays = get_nodes_in_group("lodge_room_choices").filter(func(n): return n.visible)
	check(overlays.size() == 1 and overlays[0].get_parent() == game.get_room_by_id(first), "Only legal first room must be highlighted")
	click(overlays[0])
	await process_frame
	overlays = get_nodes_in_group("lodge_room_choices").filter(func(n): return n.visible)
	check(overlays.size() == 1 and overlays[0].get_parent() == game.get_room_by_id(second), "Click must advance to second legal room")
	if not overlays.is_empty():
		click(overlays[0])
	await process_frame
	check(selected_path == [first, second], "Path callback must preserve physical click order")
	check(get_nodes_in_group("lodge_room_choices").is_empty(), "Highlights must disappear after choice")
	game.clear_player_input()
	var movement_context: Dictionary = {"caster_id": 0}
	game.request_effect_choice(0, "movement_destination", movement_context, "movement_destination_room_id", [
		{"token": "move:a", "room_id": first, "value": first},
		{"token": "move:b", "room_id": second, "value": second}
	], 1, 1, "Move selected model")
	await process_frame
	overlays = get_nodes_in_group("lodge_room_choices").filter(func(n): return n.visible and n.get_parent() == game.get_room_by_id(second))
	check(overlays.size() == 1, "Real effect request must expose destination on Lodge")
	if not overlays.is_empty():
		click(overlays[0])
	await process_frame
	check(movement_context.get("movement_destination_room_id") == second and not game.waiting_for_player_input, "Lodge click must submit the actual validated effect token")
	print("TABLETOP UI PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
