extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(not menu.avatar_setup_button.disabled, "Avatar setup must be accessible")
	menu.avatar_setup_button.pressed.emit()
	var avatar = menu.find_child("AvatarSelection", true, false)
	var difficulty = menu.find_child("AvatarDifficulty", true, false)
	var possessed := -1
	for i in avatar.item_count:
		if avatar.get_item_metadata(i) == "possessed": possessed = i
	assert(possessed >= 0, "Possessed must be selectable")
	avatar.select(possessed)
	difficulty.select(1)
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Confirm and return to menu": button.pressed.emit()
	await process_frame
	assert(menu.avatar_selection == {"id":"possessed", "difficulty":"master"})
	assert(menu.solo_count.min_value == 0 and menu.solo_count.max_value == 4)
	assert(menu.online_count.max_value == 5)
	assert(menu.menu.visible)
	assert(AvatarRules.available().any(func(d): return d.id == "possessed"), "Possessed is released")
	menu.avatar_setup_button.pressed.emit()
	menu.find_child("AvatarSelection", true, false).select(0)
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Confirm and return to menu": button.pressed.emit()
	await process_frame
	assert(menu.avatar_selection.is_empty())
	assert(menu.solo_count.min_value == 1 and menu.solo_count.max_value == 5)
	assert(menu.online_count.max_value == 6)
	menu.username.text = "Luca"
	menu.solo_count.value = 2
	menu.solo_button.pressed.emit()
	var game = menu.get_children().back()
	assert(game.player_count == 3 and game.player_display_name(0) == "Luca" and game.player_display_name(2) == "Rival 2")
	assert(game.network_session == null and game.local_viewer_index == -1)
	print("AVATAR MENU: selection, difficulty, seat limits and deactivation passed")
	quit()
