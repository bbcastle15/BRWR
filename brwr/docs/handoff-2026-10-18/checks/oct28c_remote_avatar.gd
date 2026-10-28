extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	reset_case()
	game.table_shell.set_process(false)
	var client = await create_game(true)
	client.local_viewer_index = 1
	client.beta_hud.set_process(false)
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell.open_board(0)
	# Attack and its damage can arrive in the same snapshot while the viewer
	# is browsing; opening Hand must not discard that pending damage.
	game.run_tests_on_ready = false
	game.summon_evocation(0,"colossus","black_rose")
	game.refresh_model_tokens()
	var ev = game.players[0].evocations.back()
	game.animate_model_attack(0,AVATAR,null,ev)
	game.record_damage_feedback(AVATAR,0,[0,0],0)
	var serial = game.table_feedback_serial
	game.players[AVATAR].mage.damage_cubes.assign([0,0])
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))
	expect(client.table_shell._has_damage_presentation(),"Remote Avatar damage queued after Evocation attack")
	client.beta_hud._open_hand_overlay()
	expect(client.table_shell._has_damage_presentation(),"Opening Hand preserves pending public damage")
	for tick in 100:
		await create_timer(0.1).timeout
		if client.table_shell.damage_waiting: break
	var shell = client.table_shell
	expect(shell.damage_waiting and shell.shown_player == AVATAR and shell.board_overlay.visible,"Other player sees enlarged Avatar damage and receipt")
	expect(client.avatar_board.expanded,"Damage uses actual Avatar Board")
	expect(shell.layer < client.beta_hud.layer,"Player rail never rises above Hand during damage")
	await capture("oct28c-avatar-remote-damage")
	game.acknowledge_damage(serial,1)
	# Give client an online identity so its own acknowledgement can hide its board.
	var session = load("res://online_session.gd").new()
	root.add_child(session)
	session.set_process(false)
	session.game = client
	client.network_session = session
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))
	await create_timer(0.2).timeout
	for id in ["lethal_touch","tearing","despair"]:
		client.players[1].hand.append(client.spell_database.get_spell(id))
	client.beta_hud.hand_overlay.open_preparation(client._make_parallel_preparation_request(1))
	expect(not shell.board_overlay.visible and shell.layer < client.beta_hud.layer,"Own Continue leaves Hand above rail while peers still confirm")
	client.beta_hud.hand_overlay._select_card(0)
	client.beta_hud.hand_overlay._assign_selected_numbered()
	expect(client.beta_hud.hand_overlay.ready_hand_indices == [0],"Preparation remains usable while peers confirm")
	await capture("oct28c-hand-above-rail")
	for who in [0,2]: game.acknowledge_damage(serial,who)
	NetworkSnapshot.apply(client,NetworkSnapshot.build(game,1))
	await create_timer(1.0).timeout
	expect(not shell.damage_waiting and not client.avatar_board.expanded,"Remote Avatar presentation fully releases")
	print("OCT28C REMOTE AVATAR: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
