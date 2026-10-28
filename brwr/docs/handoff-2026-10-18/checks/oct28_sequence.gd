extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	reset_case()
	game.beta_hud.panel.hide()
	game.suppress_placement_feedback = true
	game.get_node("PowerBoard").instant_updates = true
	game.players[0].available_physical_actions = 2
	game.table_shell._observe(false)
	locate(0,"black_rose")
	var destination: String = game._beta_adjacent_room_ids("black_rose")[0]
	game.queue_resolution({"type":"explore","player_index":0,"destination_room_ids":[destination],"activate_after":false,"context":{}})
	expect(game.players[0].mage.room_id=="black_rose", "Explore waits for physical token before moving")
	await create_timer(1.5).timeout
	expect(game.players[0].mage.room_id=="black_rose", "Physical token stays visible long enough")
	await create_timer(4.0).timeout
	expect(game.players[0].mage.room_id==destination, "Explore resumes movement after token and pause")
	await create_timer(2.0).timeout
	expect(game.resolution_stack.is_empty(), "Explore animation barrier releases")
	var quest_card = game.quest_database.quests.values()[0]
	var quest = QuestState.new(quest_card,0)
	quest.completed = true
	expect(game._present_resolution_card({"type":"quest_resolution","quest":quest,"player_index":0}), "Completed Quest opens presentation")
	await create_timer(2.5).timeout
	expect(not game.card_presentation.is_empty(), "Quest stays visible awaiting confirmation")
	var serial = game.card_presentation.serial
	for i in [0,1,2]: game.dismiss_card_presentation(serial,i)
	expect(game.card_presentation.is_empty(), "Quest closes after all acknowledgements")
	game.run_tests_on_ready = false
	var source = game.mage_tokens[0]
	game.animate_model_attack(0,1)
	expect(not source.visible, "Attack does not duplicate original token")
	await create_timer(1.4).timeout
	expect(source.visible, "Attack restores original token")
	for room in game.get_children():
		if not room.has_method("get_art_instability_slots"): continue
		var slots = room.get_art_instability_slots()
		expect(slots.size()==room.get_instability_resistance(), "Slot count matches " + room.room_id)
	print("OCT28 SEQUENCE: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
