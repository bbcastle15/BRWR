extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func run():
	game = await create_game()
	reset_case()
	game.beta_hud.panel.hide()
	game.players[0].mage.health = 2
	game.players[0].mage.damage_cubes.clear()
	game.deal_damage(AVATAR, 0, 2)
	var saw_receipt := false
	for tick in 180:
		await create_timer(0.1).timeout
		if game.table_shell.damage_waiting:
			saw_receipt = true
			for who in [0,1,2]: game.acknowledge_damage(game.table_shell.damage_event.serial,who)
		if game.resolution_stack.is_empty() and not game._visuals_busy(): break
	expect(saw_receipt,"Real lethal damage shows receipt")
	expect(game.resolution_stack.is_empty(),"Full defeat engine finishes")
	expect(not game.table_shell.damage_waiting and not game.table_shell.board_overlay.visible,"Defeated board releases")
	print("FULL DEFEAT: ",checks," failures ",failures," stack ",game.resolution_stack," busy ",game._visuals_busy())
	quit(0 if failures.is_empty() else 1)
