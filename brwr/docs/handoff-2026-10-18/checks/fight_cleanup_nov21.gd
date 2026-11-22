extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	reset_case()
	var hud = game.beta_hud
	game.players[0].mage.in_cell = false
	game.players[0].mage.room_id = "arena"
	game.players[1].mage.in_cell = false
	game.players[1].mage.room_id = "arena"
	var variants: Array = game._beta_fight_action_variants(0)
	var options: Array = []
	for i in variants.size():
		options.append({"token":str(i), "action":variants[i].action, "descriptor":variants[i]})
	hud.current_player_index = 0
	hud.current_request = {"type":"action_activation_step", "options":options}
	hud._set_action_menu("fight_variants")
	expect(hud.action_menu_mode == "fight_variants", "Fight waits for target selection")
	hud._set_action_menu("fight_order", {"target":{"player_index":1}})
	var labels: Array = []
	for child in hud.content.get_children():
		if child is Button: labels.append(child.text)
	expect(labels.has("Activate Room → Fight") and labels.has("Fight → Activate Room") and labels.has("Fight only"), "Selected target offers all three legal orders")
	game.players[0].available_physical_actions = 0
	var before: int = game.table_feedback_events.size()
	var returns: Array[int] = []
	game._cleanup_player_mage_sheet(0, returns)
	expect(game.players[0].available_physical_actions == PlayerState.MAX_PHYSICAL_ACTIONS, "Clean-up restores all actions")
	expect(game.table_feedback_events.size() == before, "Clean-up does not emit restore animation")
	game.players[0].available_physical_actions = 0
	game.restore_physical_actions(0, 1)
	expect(game.table_feedback_events.back().kind == "physical_restore", "Card effects retain restore animation")
	print("FIGHT/CLEANUP: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

