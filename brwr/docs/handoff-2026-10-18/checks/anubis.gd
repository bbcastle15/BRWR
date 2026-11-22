extends "res://docs/handoff-2026-10-18/checks/avatar_rules.gd"

func run():
	game = load("res://game.tscn").instantiate()
	game.player_count = 4
	game.game_seed = 20261120
	game.enable_beta_hud = false
	game.run_tests_on_ready = true
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.avatar_selection = {"id": "anubis", "difficulty": "apprentice"}
	root.add_child(game)
	for i in 4: await process_frame
	for card in game.spell_database.spells.values():
		if card.id.begins_with("anubis_") and not card.avatar_command.is_empty(): cards[card.id] = card
	expect(cards.size() == 30, "All 30 Anubis Commands loaded")
	for moon in [1, 2, 3]: expect(game.avatar.decks[moon].size() == 10, "Ten Commands per Moon")
	expect(game.players[AVATAR].mage.health == 11, "Anubis health 11")
	expect(not game.forgotten_deck.any(func(c): return c.id == "wrath_of_the_jackal_god"), "Setup removes Wrath of the Jackal God")
	reset_case()
	var jinx_context := {}
	expect(ForgottenAttachments.assign_jinx(game, 0, AVATAR, jinx_context), "Scourge resolves")
	expect(game.players[AVATAR].mage.jinxes.is_empty(), "Scourge prevents Jinx")
	damage(AVATAR, [0,0,0,0])
	game.gain_player_trophy(AVATAR, 0)
	await drive()
	expect(game.players[AVATAR].mage.get_damage() == 2, "Pledge heals two per Trophy")
	for i in 3:
		game.gain_player_trophy(AVATAR, 0)
		await drive()
	expect(game.players[AVATAR].mage.get_damage() == 0, "Pledge does not require existing damage")
	expect(game.players[AVATAR].trophies.is_empty() and game.black_rose_power == 1, "Judgment counts repeated Trophies and returns all")
	reset_case()
	game.players[0].power = 12
	game.players[1].power = 8
	expect(AvatarRules.priority(game, AvatarRules.model_options(game), 1)[0].value.player_index == 0, "Priority 1 uses Power first")
	damage(1,[0,0])
	expect(AvatarRules.priority(game, AvatarRules.model_options(game), 2)[0].value.player_index == 1, "Priority 2 uses Damage first")
	game.place_instability(0, "arena", 1)
	expect(AvatarRules.priority(game, AvatarRules.room_options(game), 3)[0].value == "arena", "Priority 3 uses Instability first")
	reset_case()
	for i in 3: game.summon_evocation(AVATAR, "pharaoh", "arena")
	locate(0, "arena")
	locate(1, "garden")
	game.summon_evocation_for_effect(AVATAR, "pharaoh", "arena", {})
	await drive()
	expect(game.players[0].mage.get_damage() == 6, "Divine Sandstorm resolves once per Evocation, even in same Room")
	expect(game.players[1].mage.get_damage() == 0, "Divine Sandstorm range zero")
	reset_case()
	game.players[AVATAR].mage.in_cell = true
	game.avatar.commands_used = 0
	game.avatar.active_deck().append(cards.anubis_torment)
	AvatarRules.begin_activation(game, false, false)
	await drive()
	expect(not game.players[AVATAR].mage.in_cell and game.avatar.commands_used == 0, "Dominion places without drawing")
	reset_case()
	locate(0, "arena")
	game.place_instability(1, "arena", 3)
	await effect({"type":"anubis_convert_instability","amount":4,"power_per_missing":1}, {"target_room_id":"arena"})
	expect(game.get_room_by_id("arena").instability_cubes == [-1,-1,-1], "Dark Ritual converts rightmost cubes")
	expect(game.black_rose_power == 1, "Dark Ritual gains Power for missing conversion")
	reset_case()
	await effect({"type":"anubis_solve_quests","amount":2})
	expect(game.players[AVATAR].completed_quests.filter(func(q): return q.is_solved()).size() == 2, "Anubis draws and solves two Quests")
	reset_case()
	game.players[0].power = 1
	await effect({"type":"anubis_steal_power","amount":3}, {"target_player_index":0})
	expect(game.players[0].power == 0 and game.black_rose_power == 1, "Steal only available Power")
	reset_case()
	damage(0,[1,1])
	await effect({"type":"anubis_defeat"}, {"target_player_index":0})
	expect(game.players[0].mage.in_cell, "Hopeless defeats without filling damage track")
	expect(game.players[1].power == 10, "Hopeless gives no defeat Power to contributors")
	# Exercise every printed section and reaction with deterministic Crown choices.
	for card in cards.values():
		for s in card.avatar_command.sections:
			reset_case()
			game.queue_resolution({"type":"avatar_section","card":card,"section":s,"context":{},"stage":"target"})
			await drive()
			expect(game.resolution_stack.is_empty(), card.card_name + " section finishes")
		var reaction: Dictionary = card.avatar_command.reaction
		if not reaction.is_empty():
			reset_case()
			var event := GameEvent.new("damage_inflicted")
			event.source_player_index = 0
			event.source_room_id = "arena"
			event.amount = 3
			var s: Dictionary = reaction.duplicate(true)
			s.kind = "reaction"
			game.queue_resolution({"type":"avatar_section","card":card,"section":s,"reaction":true,"event":event,"context":{},"stage":"target"})
			await drive()
			expect(game.resolution_stack.is_empty(), card.card_name + " reaction finishes")
	reset_case()
	expect(not AnubisRules.legendary(game), "Legendary rules are opt-in")
	game.avatar_selection.scenario = "damned_souls"
	AnubisRules.setup_scenario(game)
	expect(game.room_variants.get("sanctuary") == "sanctuary_of_anubis", "Scenario forces Sanctuary of Anubis")
	expect(game.get_node("PowerBoard").second_moon_threshold == 8 and game.get_node("PowerBoard").third_moon_threshold == 16 and game.get_node("PowerBoard").end_game_threshold == 32, "Scenario thresholds 8/16/32")
	var snapshot: Dictionary = preload("res://network_projection.gd").build(game, 0)
	expect(snapshot.power_thresholds == [8,16,32] and snapshot.avatar.id == "anubis", "Network projection includes Anubis and scenario thresholds")
	game.summon_evocation(AVATAR, "pharaoh", "arena")
	game.summon_evocation(AVATAR, "pharaoh", "arena")
	game.summon_evocation(AVATAR, "cadaver", "garden")
	await effect({"type":"anubis_sepulcher"})
	expect(game.get_room_by_id("arena").instability_cubes == [-1,-1], "Sepulcher places once per Pharaoh, including shared Room")
	expect(game.get_room_by_id("garden").instability_cubes.is_empty(), "Sepulcher excludes other Evocations")
	expect(AnubisRules.honorable_mention(game) == -1, "Honorable Mention gives no bonus on tie")
	game.players[1].trophies.append(0)
	game.players[2].trophies.append(0)
	expect(AnubisRules.honorable_mention(game) == 0, "Honorable Mention selects unique Mage with fewest trophies")
	game.players[0].power = 32
	expect(game.check_end_game(), "Scenario ends at 32 Power")
	var result_row: Dictionary = game.final_result.scores.filter(func(row): return row.player_index == 0)[0]
	expect(result_row.scenario == 2 and result_row.total == result_row.base + result_row.quests + result_row.trophies + result_row.crown + 2, "Scenario bonus is visible and included in final standings")
	game.avatar_selection.erase("scenario")
	for card in cards.values():
		expect(AvatarArt.texture(card.id) != null, card.card_name + " restored texture loads")
	for moon in [1,2,3]:
		for symbol in ["", "combat_spell", "suffered_damage"]:
			var back := AvatarArt.command_back_id(moon, {"id":"anubis", "reaction":symbol, "reaction_type":"protection"})
			expect(AvatarArt.texture(back) != null, "Back loads: " + back)
	expect(AvatarArt.texture("anubis") != null, "Avatar sheet loads")
	print("ANUBIS: %d checks; failures: %s" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func effect(data: Dictionary, context: Dictionary = {}):
	game.queue_resolution({"type":"anubis_effect","effect":data,"context":context})
	await drive()
