extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var menu = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(not menu.avatar_setup_button.disabled, "Playtest must be accessible")
	menu.avatar_setup_button.pressed.emit()
	var selections = menu.find_children("*", "OptionButton", true, false)
	var avatar = selections[0]
	var difficulty = selections[1]
	var possessed := -1
	for i in avatar.item_count:
		if avatar.get_item_metadata(i) == "possessed": possessed = i
	assert(possessed >= 0, "Possessed must be selectable")
	avatar.select(possessed)
	difficulty.select(1)
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Conferma e torna al menu": button.pressed.emit()
	await process_frame
	assert(menu.avatar_selection == {"id":"possessed", "difficulty":"master"})
	assert(menu.solo_count.min_value == 1 and menu.solo_count.max_value == 5)
	assert(menu.online_count.max_value == 5)
	assert(menu.menu.visible)
	assert(AvatarRules.available().is_empty(), "Playtest must not certify release readiness")
	menu.avatar_setup_button.pressed.emit()
	selections = menu.find_children("*", "OptionButton", true, false)
	selections[0].select(0)
	for button in menu.find_children("*", "Button", true, false):
		if button.text == "Conferma e torna al menu": button.pressed.emit()
	await process_frame
	assert(menu.avatar_selection.is_empty())
	assert(menu.solo_count.min_value == 2 and menu.solo_count.max_value == 6)
	assert(menu.online_count.max_value == 6)
	print("AVATAR MENU: selection, difficulty, seat limits and deactivation passed")
	quit()
