extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run():
	game = await create_game()
	reset_case()
	var neighbors: Array[String] = []
	for id in game.room_id_by_coord.values():
		if game.get_hex_distance(game.room_id_to_coord(id), Vector2i.ZERO) == 1:
			neighbors.append(id)
	var start: String = neighbors[0]
	var displaced: String = neighbors[1]
	locate(0, start)
	locate(1, start)
	locate(2, "black_rose")
	locate(AVATAR, start)
	game.players[1].refresh_physical_actions()
	var previous_color = game.get_room("black_rose").color
	game.get_room("black_rose").color = "red"
	var mist = game.spell_database.get_spell("cemetarial_mist")
	game.players[0].active_spells.append(ActiveSpellState.new(mist, 0, false))
	preferred["_near_room_model"] = "model:mage:1"
	preferred["_near_room_destination"] = "room:" + displaced
	preferred["explore_destination"] = "room:" + displaced
	# Exercise the real trigger window and an EMPTY Explore context.
	game.perform_explore_action(1, ["black_rose", start])
	await drive()
	expect(game.players[1].mage.room_id == displaced, "Explore resumes after trap displacement and accepts stay")
	expect(game.players[1].mage.get_damage() == 0, "Mage moved out of target Room avoids Mist damage")
	expect(game.players[2].mage.get_damage() == 3, "Mage remaining in target Room takes 3 damage")
	expect(game.players[1].available_physical_actions == 1, "Interrupted Explore spends only one physical token")
	expect(choices.any(func(c): return c.get("context_key") == "explore_destination"), "Explore offered remaining movement")
	game.get_room("black_rose").color = previous_color

	reset_case()
	locate(0, start)
	locate(1, "black_rose")
	locate(2, start)
	locate(AVATAR, start)
	var evocation = game.summon_evocation(2, "colossus", displaced)
	await drive()
	var context := {"game":game, "caster_id":0, "target_room_id":"black_rose", "spell_target_type":"room"}
	game.queue_resolution({"type":"effect_sequence", "resolver_kind":"spell", "effects":mist.light_side.effects.slice(1), "index":0, "context":context})
	expect(game.waiting_for_player_input, "Mist requests optional Model selection")
	var options: Array = game.pending_input.get("board_options", [])
	if options.is_empty(): options = game.pending_input.options
	var ev_token := ""
	for option in options:
		if str(option.token).begins_with("model:evocation:"): ev_token = option.token
	expect(not ev_token.is_empty(), "Evocation adjacent to target Room is selectable")
	expect(game.submit_effect_choice(0, ev_token), "Evocation selection accepted")
	preferred["_near_room_destination"] = "room:black_rose"
	await drive()
	expect(evocation.room_id == "black_rose", "Selected Evocation moves before damage")
	expect(evocation.get_damage() == 3, "Evocation moved into target Room takes damage")
	expect(game.players[1].mage.get_damage() == 3, "Room damage still hits Mage in original target Room")
	expect(preload("res://effect_description.gd").describe(mist.light_side.effects[1]).contains("e934_white.png"), "Effect banner uses original Model range 1 glyph")
	print("MIST PLAYTEST: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

