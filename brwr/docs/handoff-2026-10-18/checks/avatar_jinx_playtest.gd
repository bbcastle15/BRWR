extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	root.size = Vector2i(1737, 1000)
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	game.assign_mage_to_player(0, "anubis")
	game.refresh_all_player_boards()
	var board = game.player_boards[0]
	var source_size := Vector2(1671, 941)
	var art_scale: float = minf(board.MAGE_CARD_SIZE.x / source_size.x, board.MAGE_CARD_SIZE.y / source_size.y)
	for i in 2:
		var token = board.get_node("PhysicalAction%d" % i)
		var centre: Vector2 = token.position + token.size * 0.5
		var expected: Vector2 = board.get_node("MageCardSlot").position + (board.MAGE_CARD_SIZE - source_size * art_scale) * 0.5 + Vector2(233 + i * 334, 698) * art_scale
		expect(centre.distance_to(expected) < 0.1, "Anubis action centres match printed recesses")
	for i in 3: await process_frame
	game.table_shell.open_board(0)
	await capture("anubis-actions-centred")
	game.table_shell.close_board()
	var context := {"game": game, "caster_id": 0}
	var damage_before: int = game.players[AVATAR].mage.get_damage()
	ForgottenAttachments.assign_jinx(game, 0, AVATAR, context, {"id": "vulnerability"})
	expect(game.players[AVATAR].mage.get_damage() == damage_before, "FAQ p6: Vulnerability does not trigger on its own assignment")
	expect(game.card_presentation.get("kind") == "jinxs" and game.card_presentation.get("id") == "vulnerability", "Assigned Jinx uses public card presentation")
	expect(game.card_presentation.get("requires_click", false), "Jinx stays visible until acknowledged")
	expect(game.card_presentation.get("acknowledge_player") == game.crown_owner_id, "Crown acknowledges Avatar Jinx")
	await capture("jinx-assigned-presentation")
	game.dismiss_card_presentation()
	await drive()
	context = {"game": game, "caster_id": 0}
	preferred["jinx_damage"] = "inflict"
	ForgottenAttachments.assign_jinx(game, 0, AVATAR, context, {"id": "slowness"})
	expect(game.waiting_for_player_input and game.pending_input.get("context_key") == "jinx_damage", "Previously assigned Vulnerability offers damage for subsequent Jinx")
	await drive()
	# Direct test calls have no parent Effect frame to resume this function.
	ForgottenAttachments.assign_jinx(game, 0, AVATAR, context, {"id": "slowness"})
	await drive()
	expect(game.players[AVATAR].mage.get_damage() == damage_before + 1, "Chosen Vulnerability bonus inflicts exactly one damage")
	game.players[AVATAR].mage.jinxes[1].progress = 2
	game.avatar_board.refresh()
	var grid = game.avatar_board.cards_root.get_node("AvatarJinxes/Cards").get_child(0)
	expect(grid.get_child_count() == 2, "Both assigned Avatar Jinx faces are visible")
	expect(grid.get_node("slowness/Progress").get_child(1).get_child_count() == 1, "Avatar Jinx progress cubes are projected")
	game.table_shell.open_board(AVATAR)
	await capture("avatar-visible-jinxes")
	game.open_jinx_card(AVATAR, "slowness")
	expect(game._reference_card_preview().art.texture == game.ReferenceCardPreview.card_texture("jinxs", "slowness"), "Avatar Slowness opens at full size")
	game._reference_card_preview().hide_preview()
	game.table_shell.close_board()

	# Exercise the real resolver: the public reveal must resume the same Effect,
	# including Vulnerability's optional choice and the following sentence.
	reset_case()
	preferred["jinx_damage"] = "inflict"
	DruidicRules.sequence(game, [{"type": "assign_jinx", "id": "vulnerability"},
		{"type": "assign_jinx", "id": "slowness"}, {"type": "damage", "amount": 1}],
		{"game": game, "caster_id": 0, "target_player_index": AVATAR, "target_model_type": "mage"})
	expect(game.card_presentation.get("id") == "vulnerability", "Real Effect stack pauses on first assigned Jinx")
	await drive()
	expect(game.players[AVATAR].mage.jinxes.size() == 2, "Jinx reveal resumes assignment sequence without duplicate cards")
	expect(game.players[AVATAR].mage.get_damage() == 2, "Assignment sequence resumes optional bonus and next damage sentence")

	# Corrupted Spear: tied blue destinations two rooms away, with actual Crown input.
	var blue_rooms: Array = []
	for id in game.room_id_by_coord.values():
		var room = game.get_room_by_id(id)
		room.room_data = room.room_data.duplicate(true)
		room.room_data["color"] = "red"
		if AvatarRules.distance(game, "black_rose", id) == 2: blue_rooms.append(id)
	for id in blue_rooms.slice(0, 2): game.get_room_by_id(id).room_data["color"] = "blue"
	for slowed in [false, true]:
		reset_case()
		if slowed: game.players[AVATAR].mage.jinxes.append({"id": "slowness", "progress": 0})
		preferred["destination"] = "room:" + str(blue_rooms[0])
		await section("corrupted_spear", 1)
		var final_room: String = game.players[AVATAR].mage.room_id
		expect(AvatarRules.distance(game, "black_rose", final_room) == (1 if slowed else 2), "Corrupted Spear uses effective Speed: " + str(1 if slowed else 2))
		expect(final_room == blue_rooms[0] if not slowed else AvatarRules.distance(game, final_room, blue_rooms[0]) == 1, "Corrupted Spear follows chosen blue destination")
		expect(choices.any(func(r): return r.get("context_key") == "destination" and r.player_index == game.crown_owner_id), "Crown chooses among tied blue rooms")
	print("AVATAR JINX PLAYTEST: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
