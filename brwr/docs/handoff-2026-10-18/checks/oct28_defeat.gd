extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	reset_case()
	game.table_shell.set_process(false)
	var clients = [await create_game(true), await create_game(true)]
	for i in clients.size():
		clients[i].local_viewer_index = i
		var session = load("res://online_session.gd").new()
		root.add_child(session)
		session.set_process(false)
		session.game = clients[i]
		clients[i].network_session = session
		clients[i].beta_hud.set_process(false)
		NetworkSnapshot.apply(clients[i], NetworkSnapshot.build(game, i))
		clients[i].beta_hud.hand_overlay.show()
		clients[i].table_shell.open_board(0)
	var owners: Array = []
	owners.resize(game.players[0].mage.health)
	owners.fill(-1)
	game.record_damage_feedback(0, owners.size()-1, owners, AVATAR)
	var serial = game.table_feedback_serial
	# The snapshot may already contain the post-defeat, cleared health track.
	game.players[0].mage.damage_cubes.clear()
	for i in clients.size(): NetworkSnapshot.apply(clients[i], NetworkSnapshot.build(game, i))
	await create_timer(5.0).timeout
	for i in clients.size():
		var shell = clients[i].table_shell
		expect(shell.damage_waiting, "Client %d presents lethal damage despite open Hand" % i)
		expect(shell.damage_receipt.visible and shell.receipt_buttons.get_child_count()==1, "Client %d has Continue" % i)
		expect(shell.damage_event.get("announced",false), "Client %d announced defeat" % i)
	game.acknowledge_damage(serial,1)
	for i in clients.size(): NetworkSnapshot.apply(clients[i],NetworkSnapshot.build(game,i))
	await create_timer(0.2).timeout
	expect(clients[0].table_shell.damage_receipt.visible, "Defeated player still has their own Continue")
	expect(not clients[1].table_shell.damage_receipt.visible, "Other player's receipt hides only after their own acknowledgement")
	game.acknowledge_damage(serial,0)
	game.acknowledge_damage(serial,2)
	for i in clients.size(): NetworkSnapshot.apply(clients[i],NetworkSnapshot.build(game,i))
	await create_timer(1.5).timeout
	for i in clients.size():
		var shell = clients[i].table_shell
		expect(not shell.damage_waiting and not shell.board_overlay.visible, "Client %d leaves defeated board after acknowledgements" % i)
		expect(not shell.visuals_busy(), "Client %d resolution barrier released" % i)
	print("OCT28 DEFEAT: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
