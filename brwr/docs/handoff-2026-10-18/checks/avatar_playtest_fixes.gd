extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func _initialize():
	call_deferred("run")
	create_timer(180).timeout.connect(func(): push_error("Avatar playtest fixes timeout"); quit(2))

func run():
	root.size = Vector2i(1737,1000)
	game = await create_game()
	reset_case()
	game.local_viewer_index = 0
	var ev = game.summon_evocation(AVATAR, "colossus", "black_rose")
	await drive()
	ev.damage_cubes.assign([0,1])
	game.avatar_board.refresh()
	game.table_shell.open_board(AVATAR)
	expect(is_equal_approx(game.avatar_board.rotation, -PI/2), "Avatar Board is portrait, printed card text upright")
	expect(game.avatar_board.get_node("HealthLimit").get_child(0) is Line2D, "Health limit outline does not cover damage")
	var ev_card = game._evocation_board_card(AVATAR, ev)
	expect(ev_card.get_node("EvocationDamage").get_child_count() == 2, "Damage cubes appear on Avatar's Evocation card")
	await capture("avatar-portrait-fixed")
	game.table_shell.open_board(0)
	expect(game.show_board_target_choice({"token":"evocation:3:0", "owner_id":AVATAR,"evocation_index":0},func():pass), "Avatar Evocation choice has a clickable card")
	expect(not game.table_shell.board_overlay.visible, "Avatar Evocation is selected on the Lodge without opening board")
	var highlights = get_nodes_in_group("board_target_choices")
	expect(not highlights.is_empty() and game.evocation_tokens[ev.get_instance_id()].is_ancestor_of(highlights.back()), "Target hitbox belongs to Avatar Evocation token")
	game.clear_board_target_choices()
	var before: Vector2 = game.evocation_tokens[ev.get_instance_id()].position
	var destination: String = game._beta_adjacent_room_ids("black_rose")[0]
	expect(game.move_evocation_to_room_id(ev, destination, 1), "Evocation can move")
	expect(not game.table_shell.board_overlay.visible, "Evocation movement reveals Lodge")
	expect(game.evocation_tokens[ev.get_instance_id()].has_meta("movement_tween"), "Evocation movement is animated")
	await create_timer(0.4).timeout
	expect(not game.evocation_tokens[ev.get_instance_id()].position.is_equal_approx(before), "Movement visibly reaches destination")

	reset_case()
	var context := {}
	var upgrades: Array = []
	for id in ["pegasus_feathers","regenerating_ichor","reinforced_dermis","skinblade","tendon_implant","warscratch"]:
		upgrades.append({"token":"upgrade:"+id, "value":id, "id":id, "card_kind":"upgrades", "name":id.capitalize()})
	game.request_effect_choice(0,"upgrade",context,"upgrade",upgrades,1,1,"Choose an Upgrade.")
	var gallery = game.beta_hud.content.get_node("ObjectChoices")
	expect(gallery.get_child(0) is GridContainer, "Upgrades use a grid")
	var grid = gallery.get_child(0)
	expect(grid.columns <= 3, "Upgrade grid has readable columns")
	for card in grid.get_children():
		expect(card.custom_minimum_size.x >= 400 and card.custom_minimum_size.x > card.custom_minimum_size.y, "Upgrade slots match landscape card aspect")
	await capture("upgrade-grid-fixed")

	reset_case()
	for i in AVATAR: game.players[i].mage.in_cell = true
	game.summon_evocation(AVATAR,"colossus","black_rose")
	await drive()
	var frame := {"evocation":game.players[AVATAR].evocations[0],"controller_id":AVATAR,"context":{}}
	expect(not AvatarRules.prepare_evocation(game,frame), "AI exposes tied movement plans to Crown")
	var request: Dictionary = game.pending_input
	expect(request.player_index == game.crown_owner_id, "Only Crown chooses Avatar plan")
	var options: Array = request.get("options", request.get("board_options", []))
	expect(options.any(func(o): return not o.get("path",[]).is_empty()), "Public AI plans retain path addresses")
	expect(not get_nodes_in_group("lodge_room_choices").is_empty(), "Pending Avatar decision has actual clickable Rooms")
	for i in 5:
		if not game.waiting_for_player_input: break
		var buttons = get_nodes_in_group("lodge_room_choices").filter(func(b): return not b.is_queued_for_deletion())
		if buttons.is_empty(): break
		buttons[0].chosen.emit()
		await process_frame
	expect(not game.waiting_for_player_input, "Crown can complete pending choice through board UI")

	reset_case()
	var minotaur = game.summon_evocation(0,"minotaurus","black_rose")
	await drive()
	game.current_phase = game.PHASE_EVOCATION
	game.current_phase_play_order.assign([0])
	var mino_data := {"evocation_index":0,"name":"Minotaurus", "activation_plans":game._beta_evocation_activation_plans(minotaur,0)}
	game.request_player_input({"type":"evocation_phase_activations","phase":game.PHASE_EVOCATION,"player_index":0,"evocations":[mino_data]})
	game.beta_hud._render_evocation_movement(mino_data)
	for i in 3: await process_frame
	expect(game.pending_input.get("context_key") == "order", "Forgotten activation starts with real order choice, no dummy room selection")

	reset_case()
	game.players[0].available_physical_actions = 1
	minotaur = game.summon_evocation(0,"minotaurus","black_rose")
	await drive()
	var descriptor: Dictionary = game._beta_command_action_variants(0)[0]
	var option := {"token":"action:0", "kind":"action", "action":descriptor.action.duplicate(true), "descriptor":descriptor.duplicate(true), "label":descriptor.label}
	game.action_activation_active = true
	game.action_activation_player_index = 0
	game.request_player_input({"type":"action_activation_step","phase":game.PHASE_ACTION,"player_index":0,"options":[option]})
	game.beta_hud.action_menu_mode = "physical"
	game.beta_hud._render_current_request()
	expect(not get_nodes_in_group("board_target_choices").is_empty(), "Physical token Command highlights Forgotten Evocation")
	var session = load("res://online_session.gd").new()
	session.avatar_selection = {"id":"possessed"}
	expect(session.host(6) == ERR_INVALID_PARAMETER, "Online rejects six humans plus Avatar")
	session.free()
	print("AVATAR PLAYTEST FIXES: ",checks," assertions; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
