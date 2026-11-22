extends SceneTree

func _initialize():
	call_deferred("run")

func select_avatar(menu, mode: String, id: String):
	menu._open_avatar_setup(mode)
	var option = menu.find_child("AvatarSelection", true, false)
	for i in option.item_count:
		if mode == "solo": assert(option.get_item_metadata(i) != "", "Solo requires an Avatar")
		if option.get_item_metadata(i) == id:
			option.select(i)
			option.item_selected.emit(i)
	menu.find_child("AvatarDifficulty", true, false).select(1)

func confirm(menu):
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Confirm and return to menu": button.pressed.emit()
	await process_frame

func run():
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.online_avatar_button != null and menu.online_room_button != null)
	select_avatar(menu, "online", "anubis")
	menu.find_child("DamnedSoulsScenario", true, false).button_pressed = true
	await confirm(menu)
	assert(menu.online_avatar_selection == {"id":"anubis", "difficulty":"master", "scenario":"damned_souls"})
	assert(menu.online_count.max_value == 5)
	assert(menu.avatar_selection.is_empty() and menu.solo_avatar_selection.id == "possessed")
	menu.online_room_button.pressed.emit()
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Random variants": button.pressed.emit()
	await confirm(menu)
	assert(not menu.online_room_selections.is_empty())
	assert(menu.room_selections.is_empty() and menu.solo_room_selections.is_empty())
	select_avatar(menu, "solo", "anubis")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("res://../build-user-data/avatar_chooser_nov21.png")
	await confirm(menu)
	assert(menu.solo_avatar_selection == {"id":"anubis", "difficulty":"master"})
	assert(menu.online_avatar_selection.get("scenario") == "damned_souls")
	menu.session.connection_started = 1
	menu._refresh_lobby()
	assert(menu.online_avatar_button.disabled and menu.online_room_button.disabled and menu.solo_avatar_button.disabled)
	menu.session.connection_started = 0
	menu._refresh_lobby()
	menu.username.text = "Solo tester"
	menu.avatar_solo_start.pressed.emit()
	var game = menu.get_children().back()
	assert(game.player_count == 2 and game.local_match_mode == "solo")
	assert(game.avatar_selection.id == "anubis" and game.avatar_selection.difficulty == "master")
	print("AVATAR MODES: Solo Anubis launch, Online controls, independent room/Avatar selections and connection locks passed")
	quit()
