extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	root.size = Vector2i(1440, 1000)
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	check(menu.mode_pages.size() == 3, "Three menu modes")
	check(menu.mode_pages.local.visible and not menu.mode_pages.solo.visible, "Local initially selected")
	menu._show_mode("solo")
	check(menu.mode_pages.solo.visible and not menu.mode_pages.online.visible, "Solo opens its setup")
	menu.solo_room_button.pressed.emit()
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Deep Black Rose Room": button.pressed.emit()
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Confirm and return to menu": button.pressed.emit()
	await process_frame
	check(menu.mode_pages.solo.visible and menu.solo_room_selections.get("black_rose") == "deep_black_rose" and menu.room_selections.is_empty(), "Solo room choice is independent of Local")
	check(menu.school_checks.size() >= 6, "Playable Schools listed")
	for i in 6: menu.school_checks[i].button_pressed = true
	check(menu.forced_school_ids.size() == 6, "Six Schools selected")
	check(menu.school_checks.slice(6).all(func(c): return c.disabled), "Unselected Schools disabled at limit")
	menu.school_checks[0].button_pressed = false
	check(menu.school_checks.slice(6).all(func(c): return not c.disabled), "Unchecking frees selection")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/handoff-2026-10-18/evidence/nov13-menu-solo.png")
	menu.username.text = "Beta tester"
	menu._start_avatar_solo()
	await process_frame
	await process_frame
	var match_game = null
	for child in menu.get_children():
		if child.get_script() == load("res://game.gd"): match_game = child
	check(match_game != null, "Solo creates a game")
	if match_game != null:
		check(match_game.player_count == 2 and match_game.avatar != null and match_game.avatar.player_index == 1, "Solo creates exactly one human against Avatar")
		check(menu.forced_school_ids.all(func(id): return match_game.active_school_ids.has(id)), "Menu forwards forced Schools into match")
		check(match_game.get_room_by_id("black_rose").get_art_id() == "deep_black_rose", "Solo places the selected alternative tile on the Lodge")
	print("NOV13 MENU: %d failures" % failures.size())
	menu.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
