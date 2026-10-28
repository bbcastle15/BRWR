extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	root.size = Vector2i(1296, 589)
	game = await create_game()
	reset_case()
	var hud = game.beta_hud
	hud.set_process(false)
	hud._on_player_input_requested({"type":"study_choose_schools","player_index":0,"active_school_ids":["death","chaos","druidic","agony","forge","lex"]})
	for i in 12: await process_frame
	var row = hud.content.get_node("StudyRow")
	var card = row.get_child(0).get_child(0).get_child(0).get_child(0)
	var rect = card.get_global_rect()
	for i in 4:
		hud._add_study_school("death")
		await process_frame
		expect(hud.content.get_node("StudyRow") == row and card.get_global_rect() == rect, "Library selection keeps card identity and dimensions")
	expect(not row.get_child(1).get_child(2).disabled, "Fourth draw enables Confirm")
	hud._undo_study_school()
	expect(row.get_child(1).get_child(2).disabled, "Undo disables Confirm")
	hud._clear_study_schools()
	expect(hud.school_draft.is_empty() and row.get_child(1).get_child(0).disabled, "Clear resets draft in place")
	hud.panel.hide()
	game._log_phase_choice(0,"study_keep_cards",{"keep_indices":[0,1]})
	expect(game.public_history.back().messages[0] == "Chose to keep 2 drawn Spells.", "Study choices logged without hidden card identities")
	var history_size = game.public_history.size()
	game.waiting_for_player_input = false
	game._submit_beta_input_authoritative(0,{"keep_indices":[0,1]})
	expect(game.public_history.size() == history_size, "Rejected choices are not logged")
	game.add_history_entry({"kind":"choice","title":"Effect choice","player":0})
	game.request_effect_choice(0,"test_choice",{},"test_choice",[{"token":"test_room","label":"Garden","value":"garden"}],1,1,"Choose a room.")
	game.pending_input["effect_description"] = "Place 1 Instability."
	game.submit_effect_choice(0,"test_room")
	expect(game.public_history.back().messages.any(func(m): return m.contains("chose Garden") and m.contains("Place 1 Instability")), "Effect choices include target and resolving effect")
	var shell = game.table_shell
	for owner in [0,AVATAR]:
		shell._observe(false)
		game.players[owner].trophies.append(1)
		shell._observe(true)
		expect(shell.animation_queue.any(func(e): return e.kind == "trophy" and e.player == owner), "Trophy award queues for Player or Avatar")
		shell._play_next_animation()
		expect(shell.animated_trophy_ghost and shell.board_overlay.visible, "Trophy animates on enlarged board")
		await create_timer(2.0).timeout
		expect(not shell.animated_trophy_ghost, "Trophy ghost cleaned after landing")
	# A stalled peer must not permanently retain the defeat receipt.
	game.record_damage_feedback(0,0,[1],1)
	for i in 40:
		await create_timer(0.1).timeout
		if shell.damage_waiting: break
	expect(shell.damage_waiting, "Receipt is presented before deadline")
	var serial = int(shell.damage_event.get("serial",-1))
	await create_timer(10.3).timeout
	expect(game.damage_acknowledgements.get(str(serial),[]).is_empty(), "Unresponsive peer confirmation expires")
	expect(not shell.damage_waiting and not shell.board_overlay.visible, "Expired receipt releases enlarged board")
	var source := Node2D.new()
	var target := Node2D.new()
	game.add_child(source)
	game.add_child(target)
	source.position = Vector2(100,100)
	target.position = Vector2(300,150)
	var origin := source.global_position
	var destination := target.global_position
	var direction := origin.direction_to(destination)
	game._play_attack_ghost(source,origin,destination,target)
	var ghost = game.get_child(game.get_child_count()-1)
	await create_timer(0.10).timeout
	expect((ghost.global_position-origin).dot(direction)<-1, "Attack winds up backwards")
	await create_timer(0.45).timeout
	expect(absf(ghost.global_position.distance_to(destination)-23)<1, "Impact overlaps half target diameter")
	expect(target.global_position.distance_to(destination)>0, "Target visibly recoils")
	await create_timer(0.8).timeout
	expect(source.visible and target.position.is_equal_approx(destination), "Attack restores source and target")
	print("OCT28B FEEDBACK: ", checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
