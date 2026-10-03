extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(8): await process_frame
	var board = game.get_node("EventBoard")
	check(board.get_node("EventBoardArt").size == board.ART_SIZE, "Texture respects board geometry")
	check(not board.get_node("BoardShape").visible and not board.get_node("Title").visible, "No placeholder board or title over the art")
	var connection: Vector2 = game.hex_to_pixel(Vector2i(-2, 1)) - Vector2(game.HEX_RADIUS, 0)
	check((board.position + board.LODGE_NOTCH).is_equal_approx(connection), "Event Board notch aligns to Lodge")
	check(board.get_node("ActiveEvent3").position.y < board.get_node("ActiveEvent2").position.y and board.get_node("ActiveEvent2").position.y < board.get_node("ActiveEvent1").position.y, "Event order matches physical board")
	game.active_events.assign([game.event_database.get_event("awakening"), game.event_database.get_event("growth"), game.event_database.get_event("only_war")])
	game.event_discard.append(game.event_database.get_event("hidden_resources"))
	board.refresh_event_slots()
	for i in range(3):
		var slot = board.get_node("ActiveEvent" + str(i + 1))
		var view = slot.get_node("EventView")
		check(view.size == slot.size, "Event card fits its physical slot")
		view.pressed.emit()
		var preview = game.get_node("ReferenceCardPreview")
		check(preview.root.visible and preview.title_label.text == game.active_events[i].event_name, "Active Event inspection opens correct card")
	board.get_node("EventDiscardSlot/EventView").pressed.emit()
	check(game.get_node("ReferenceCardPreview").title_label.text == "Hidden Resources", "Discard is inspectable")
	var quest = game.quest_database.get_quest("indigo_star")
	game.quest_discard.append(quest)
	game.black_rose_trophies.assign([0, 1, 0])
	game.refresh_all_player_boards()
	check(board.get_node("BlackRoseTrophySlot").get_child_count() == 3, "Trophies project actual owners and duplicates")
	board.get_node("QuestDiscardSlot/QuestView").pressed.emit()
	check(game.get_node("ReferenceCardPreview").title_label.text == "Indigo Star", "Quest discard opens public card")
	board.set_black_rose_cube_count(30)
	check(board.take_black_rose_cubes(7) == 7, "Existing cube pool API preserved")
	var visible_cubes := 0
	for child in board.get_node("BlackRoseCubePool").get_children():
		if child.name != "CountLabel" and child.visible:
			visible_cubes += 1
	check(visible_cubes == 23, "Reserve shows one cube for each available cube")
	board.return_black_rose_cubes(7)
	check(board.black_rose_cube_count == 30, "Cubes return to reserve")
	game.active_events.assign([null, null, null])
	game.event_discard.clear()
	game.quest_discard.clear()
	game.black_rose_trophies.clear()
	board.refresh_event_slots()
	check(board.get_node("ActiveEvent1").get_node_or_null("EventView") == null, "Refresh removes stale Event views")
	check(board.get_node("QuestDiscardSlot").get_node_or_null("QuestView") == null and board.get_node("BlackRoseTrophySlot").get_child_count() == 0, "Empty support slots clear correctly")
	await process_frame
	print("EVENT BOARD: ", "PASS" if failures == 0 else "FAIL " + str(failures))
	quit(0 if failures == 0 else 1)
