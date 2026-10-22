extends "res://docs/handoff-2026-10-18/checks/avatar_rules.gd"

const NetworkSnapshot = preload("res://network_projection.gd")

func create_game(client: bool = false):
	var instance = load("res://game.tscn").instantiate()
	instance.player_count = 4
	instance.game_seed = 182026
	instance.enable_beta_hud = false
	instance.run_tests_on_ready = true
	instance.auto_start_game_flow = false
	instance.beta_force_fullscreen = false
	instance.network_client = client
	instance.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	root.add_child(instance)
	for i in 4: await process_frame
	return instance

func assigned(id: String, slot: int):
	ForgottenEvocations.resolve_assignment(game, {"type":"assign_nightmare", "evocation_id":id},
		{"game":game, "caster_id":0, "target_player_index":AVATAR, "nightmare_slot":slot})
	return game.players[AVATAR].evocations.back()

func command(id: String):
	var card: SpellCardState = cards["possessed_" + id]
	game.queue_resolution({"type":"avatar_command", "card":card, "sections":card.avatar_command.sections, "index":0})
	await drive()

func run():
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	expect(AvatarRules.human_order(game) == [0,1,2], "Avatar excluded from human-only phases")
	expect(not game.take_crown(AVATAR), "Avatar cannot take Crown")
	expect(game.crown_owner_id == 0, "Crown remains human")
	expect(game.quest_manager.draw_phase_quest(game, AVATAR) == null, "Avatar does not draw ordinary phase Quest")

	# Distances, ties, priority 3 excludes own Models.
	locate(0, "garden")
	locate(1, "arena")
	locate(2, "crypt")
	damage(1, [0,0])
	var candidates: Array = AvatarRules.priority(game, AvatarRules.model_options(game), 1)
	expect(candidates.size() == 1 and candidates[0].value.player_index == 1, "Priority 1 chooses most damaged Mage")
	for i in AVATAR: locate(i, "garden")
	game.summon_evocation(AVATAR, "cadaver", "black_rose")
	await drive()
	candidates = AvatarRules.priority(game, AvatarRules.room_options(game), 3)
	expect(candidates.size() == 1 and candidates[0].value == "garden", "Priority 3 ranks human presence above own Models")

	reset_case()
	locate(AVATAR, "arena")
	await command("release_energy")
	expect(game.players[AVATAR].mage.room_id == "black_rose", "Movement precedes Room spell")
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1,-1], "Room spell uses final movement position")

	reset_case()
	arm("release_energy")
	game.place_mage_in_cell(AVATAR)
	await drive()
	AvatarRules.begin_activation(game, false, false)
	await drive()
	expect(game.players[AVATAR].mage.room_id == "black_rose" and not game.players[AVATAR].mage.in_cell, "Dominion returns from Cell")
	expect(game.avatar.commands_used == 0 and game.avatar.active_deck().size() == 1, "Dominion neither draws nor spends Command")
	AvatarRules.begin_activation(game, false, false)
	await drive()
	expect(game.avatar.commands_used == 1 and game.avatar.active_deck().is_empty(), "Next activation executes normal Command")

	reset_case()
	# Keep this case in Moon 1; Moon changes are exercised separately below.
	for p in game.players: p.power = 0
	arm("release_energy")
	game.avatar.active_deck().append(cards.possessed_energy_of_the_rose)
	AvatarRules.begin_activation(game, false, false)
	await drive()
	expect(game.avatar.commands_used == 1 and game.players[AVATAR].memories.size() == 2, "Additional Command does not count toward limit")
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1,-1], "Additional Command actually resolves")

	reset_case()
	for p in game.players: p.power = 0
	game.black_rose_power = 5
	arm("energy_of_the_rose")
	game.avatar.decks[2].append(cards.possessed_release_force)
	AvatarRules.begin_activation(game, false, false)
	await drive()
	expect(game.current_moon == 2, "Power immediately changes Moon")
	expect(game.players[AVATAR].memories.map(func(c): return c.id) == ["possessed_energy_of_the_rose", "possessed_release_force"], "Additional Command uses new Moon deck")
	game.avatar.decks[1].append(cards.possessed_corrupted_ray)
	game.avatar.decks[2].append(cards.possessed_blaze)
	game.avatar.recycle_memories()
	expect(game.avatar.decks[1].size() == 2 and game.avatar.decks[2].size() == 2, "Cleanup returns each Command to original Moon")
	expect(game.avatar.decks[1].back().id == "possessed_corrupted_ray" and game.avatar.decks[2].back().id == "possessed_blaze", "Cleanup keeps undrawn cards above recycled cards")
	expect(game.players[AVATAR].memories.is_empty(), "Cleanup clears Memories")

	for difficulty in ["apprentice", "master"]:
		reset_case()
		game.avatar.difficulty = difficulty
		for p in game.players:
			p.power = 0
			p.available_physical_actions = 0
		for i in 5: game.avatar.active_deck().append(game.clone_spell_card(cards.possessed_release_energy))
		game.resolve_action_phase()
		await drive()
		expect(game.avatar.commands_used == (3 if difficulty == "apprentice" else 4), difficulty + " completes exact Command budget even after humans finish")
		expect(game.current_phase_play_order.is_empty(), difficulty + " Action phase ends")

	reset_case()
	var first = game.summon_evocation(AVATAR, "cadaver", "black_rose")
	var second = game.summon_evocation(AVATAR, "colossus", "black_rose")
	await drive()
	game.players[AVATAR].evocations.reverse() # array order must not override slots
	game.resolve_evocation_phase()
	await drive()
	expect(game.evocation_phase_activated.is_empty(), "Evocation phase finishes and clears activation list")
	expect(game.players[0].mage.get_damage() == 5, "Avatar activates both Evocations using target priorities")
	expect(first.board_number == 1 and second.board_number == 2, "Evocation slot numbers remain stable")

	reset_case()
	var ordinary = game.summon_evocation(AVATAR, "colossus", "black_rose")
	var umbra = assigned("umbra", ordinary.board_number)
	assigned("umbra", 2)
	await drive()
	ForgottenEvocations.process_nightmare_attack(game, {"evocation":umbra, "controller_id":-1})
	await drive()
	expect(game.players[AVATAR].mage.get_damage() == 0 and ordinary.get_damage() == 0, "Umbra also spares Avatar's assigned-slot Evocation")
	game.players[AVATAR].mage.jinxes.append({"id":"slowness", "progress":0})
	game.queue_resolution({"type":"avatar_cleanup"})
	await drive()
	expect(game.players[AVATAR].evocations.size() == 2 and ordinary in game.players[AVATAR].evocations, "Cleanup removes exactly one assigned Evocation; ordinary summons stay")
	expect(game.players[AVATAR].mage.jinxes[0].progress == 1, "Cleanup progresses each Jinx")
	expect(game.players[AVATAR].available_cubes == 29, "Jinx uses shared BR pool")

	# Event-specific branches beyond the basic event/rules suite.
	reset_case()
	game.players[0].trophies.append(AVATAR)
	await event_effect("cursed_trophy")
	expect(game.players[0].power == 9 and game.players[1].power == 10, "Cursed Trophy penalizes only Avatar Trophy holders")
	reset_case()
	game.summon_evocation(0, "cadaver", "black_rose")
	await drive()
	preferred["choice"] = "lose_power"
	await event_effect("revolt_of_the_servants")
	expect(game.players[0].power == 9 and game.players[0].evocations.size() == 1, "Revolt permits losing Power instead of own Evocation")
	reset_case()
	var sacrifice = game.summon_evocation(0, "cadaver", "black_rose")
	await drive()
	preferred["choice"] = "evocation:%d" % sacrifice.get_instance_id()
	await event_effect("revolt_of_the_servants")
	expect(game.players[0].power == 10 and game.players[0].evocations.is_empty(), "Revolt removes selected own Evocation")

	for entry in [["letters_of_destruction","garden"],["conspiracy_book","armory"]]:
		reset_case()
		game.active_events[1] = event_card(entry[0])
		game.activate_room(0, entry[1], false, {"avatar_no_room_effect":true})
		await drive()
		expect(game.players[0].power == 11 and game.players[0].mage.get_damage() == 1, entry[0] + " activates for matching Room color")
	reset_case()
	var quest: QuestState = game.quest_manager.draw_quest(game, 0)
	game.players[0].active_quests.erase(quest)
	quest.complete()
	quest.solve()
	game.players[0].completed_quests.append(quest)
	await event_effect("manipulating_the_past")
	expect(game.players[0].completed_quests.is_empty() and quest.card in game.quest_discard, "Manipulating the Past discards solved Quest")

	reset_case()
	for moon in [1,2,3]:
		for card in cards.values():
			if int(card.avatar_command.moon) == moon: game.avatar.decks[moon].append(card)
	game.avatar.commands_used = 1
	game.players[AVATAR].memories.append(game.avatar.active_deck().pop_back())
	damage(AVATAR, [0,1])
	game.summon_evocation(AVATAR, "cadaver", "garden")
	await drive()
	var state: Dictionary = NetworkSnapshot.build(game, 0)
	expect(not state.players[AVATAR].has("hand"), "Online snapshot never reveals Avatar deck identities")
	expect(not state.avatar.has("decks") and state.avatar.deck_counts[1] == 9, "Online snapshot contains counts, not deck order")
	var wire = Marshalls.base64_to_variant(Marshalls.variant_to_base64(state, false), false)
	var client = await create_game(true)
	NetworkSnapshot.apply(client, wire)
	expect(client.players[AVATAR].mage.damage_cubes == [0,1], "Client receives Avatar damage")
	expect(client.avatar.commands_used == 1 and client.avatar.decks[1].size() == 9 and client.avatar.decks[2].size() == 10, "Client receives Command counts across all Moons")
	expect(client.players[AVATAR].memories.size() == 1 and client.players[AVATAR].memories[0].id == game.players[AVATAR].memories[0].id, "Client receives revealed Memories")
	expect(client.players[AVATAR].evocations.size() == 1 and client.players[AVATAR].evocations[0].room_id == "garden", "Client receives Avatar Evocation")
	expect(client.avatar.active_deck().all(func(c): return c == null), "Client does not retain locally shuffled hidden Commands")
	client.queue_free()
	await process_frame
	print("AVATAR FLOW: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
