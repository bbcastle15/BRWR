extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func solved_quest(owner: int, id: String):
	var quest := QuestState.new(game.quest_database.quests[id], owner)
	quest.complete()
	game.players[owner].completed_quests.append(quest)
	game.quest_manager.solve_quest(game, owner, quest)
	await drive()
	return quest

func sinkhole(owner: int, room: String):
	var spell: SpellCardState = game.spell_database.get_spell("arcane_sinkhole")
	game.queue_resolution({"type":"effect_sequence", "resolver_kind":"spell",
		"effects":spell.dark_side.effects, "index":0,
		"context":{"game":game, "caster_id":owner, "caster_room_id":game.players[owner].mage.room_id,
		"target_room_id":room, "spell_target_type":"room", "spell_type":"combat", "spell_id":spell.id}})
	await drive()

func run():
	root.size = Vector2i(1600,1000)
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	for owner in [0, AVATAR]:
		game.players[owner].mage.jinxes.append({"id":"inverted_pyramid", "progress":0})
		await solved_quest(owner, "acquire_wealth")
	expect(game.players[0].mage.get_damage() == 2, "Inverted Pyramid damages human on solving Quest")
	expect(game.players[AVATAR].mage.get_damage() == 0, "Avatar immune to Black Rose damage from Inverted Pyramid")
	reset_case()
	for owner in [0, AVATAR]:
		game.players[owner].mage.jinxes.append({"id":"weakness", "progress":0})
		game.place_mage_in_cell(owner)
		await drive()
	expect(game.players[0].mage.get_damage() == 2, "Weakness damages human on Cell entry")
	expect(game.players[AVATAR].mage.get_damage() == 0, "Avatar immune to Black Rose damage from Weakness")

	reset_case()
	var treasure := ""
	for data in game.room_database:
		if data.id == "templars_treasure_room": treasure = data.id
	expect(not treasure.is_empty(), "Templar treasure definition found")
	# Make the specified Room available in this seeded Lodge without changing geometry.
	var previous: String = game.room_id_by_coord.values()[0]
	var coord: Vector2i = game.room_id_to_coord(previous)
	var room = game.get_room_by_id(previous)
	var old_id: String = room.room_id
	room.room_id = treasure
	room.set_meta("room_id", treasure)
	game.room_id_by_coord[coord] = treasure
	locate(0, treasure)
	await solved_quest(0, "acquire_wealth")
	expect(room.get_instability_count() == 1, "Acquire Wealth places Instability in current Templar treasure Room")
	room.room_id = old_id
	room.set_meta("room_id", old_id)
	game.room_id_by_coord[coord] = old_id

	reset_case()
	locate(0, "garden")
	locate(1, "black_rose")
	locate(2, "garden")
	locate(AVATAR, "garden")
	# Use a rebuilt blue Room to isolate Geoform from its inability to hold cubes.
	room = game.get_room_by_id("black_rose")
	var old_color = game.get_room("black_rose").color
	game.get_room("black_rose").color = "blue"
	room.flipped = true
	await sinkhole(0, "black_rose")
	expect(game.players[1].mage.get_damage() == 4, "Arcane Sinkhole deals 2 + 2 on rebuilt blue Room")
	await sinkhole(0, "black_rose")
	expect(game.players[1].mage.get_damage() == 8, "Second copy deals another 2 + 2")
	expect(room.get_instability_count() == 0, "Rebuilt Room receives no Instability")
	game.get_room("black_rose").color = old_color

	reset_case()
	locate(0, "garden")
	locate(1, "black_rose")
	locate(2, "garden")
	locate(AVATAR, "garden")
	room = game.get_room_by_id("black_rose")
	game.get_room("black_rose").color = "blue"
	room.flipped = true
	game.players[0].available_cubes = 1
	await sinkhole(0, "black_rose")
	expect(game.players[1].mage.get_damage() == 1, "Damage is capped by one available cube")
	await sinkhole(0, "black_rose")
	expect(game.players[1].mage.get_damage() == 1, "No damage when caster cube pool is exhausted")
	game.get_room("black_rose").color = old_color

	reset_case()
	game.players[AVATAR].mage.in_cell = true
	var colossus = game.summon_evocation(AVATAR, "colossus", "black_rose")
	await drive()
	game.current_phase = game.PHASE_ACTION
	game.resolve_evocation_phase()
	expect(not game.current_phase_play_order.is_empty() and game.current_phase_play_order.front() == AVATAR, "Avatar Evocations act first even with Avatar in Cell")
	await drive()
	expect(game.evocation_phase_activated.is_empty(), "Colossus activation resolves and phase completes")
	expect(game.players[0].mage.get_damage() > 0, "Avatar Colossus attacks legal target")

	reset_case()
	# Finish the preceding damage presentation before testing manual board opening.
	game.table_shell.close_board()
	game.avatar_board.refresh()
	game.table_shell.open_board(AVATAR)
	expect(is_equal_approx(game.avatar_board.rotation, -PI/2), "Fullscreen Avatar Board is exactly upright")
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarMemories") == null, "Empty Memories have no card back")
	expect(game.avatar_board.cards_root.get_node_or_null("AvatarJinxes") == null, "No empty Jinx label")
	await capture("avatar-fourth-board")
	game.table_shell.close_board()
	for pair in [["avatars","possessed"],["events","avatar_divinatory_secrets"],["spells","possessed_frost_spear"]]:
		var preview = game._reference_card_preview()
		preview.show_card(pair[0], pair[1], pair[1], "")
		expect(not preview.art.texture is AtlasTexture, "Preview loads actual restored PNG: " + pair[1])
		await capture("avatar-fourth-" + pair[1])
		preview.hide_preview()
	print("AVATAR FOURTH PLAYTEST: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)


