extends SceneTree

# Isolated scenarios: targets, decks, cubes and trigger windows are reset
# between cases. This complements (rather than replaces) the startup smoke.
var game
const AVATAR := 3
var checks := 0
var failures: Array[String] = []
var choices: Array = []
var preferred: Dictionary = {}
var cards: Dictionary = {}

func _initialize():
	call_deferred("run")
	create_timer(120).timeout.connect(func(): push_error("Avatar rules timeout"); quit(2))

func expect(ok: bool, label: String):
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func locate(id: int, room: String):
	var mage: MageState = game.players[id].mage
	mage.in_cell = false
	mage.room_id = room
	mage.room_coord = game.room_id_to_coord(room)

func damage(id: int, owners: Array):
	for owner in owners:
		game.take_owner_cubes(int(owner), 1)
		game.players[id].mage.damage_cubes.append(int(owner))

func reset_case():
	game.resolution_stack.clear()
	game.clear_player_input()
	game.trigger_window_active = false
	game.trigger_window_queue.clear()
	game.trigger_window_stack.clear()
	game.current_phase = game.PHASE_ACTION
	game.current_moon = 1
	game.crown_owner_id = 0
	game.current_phase_play_order.assign([0, 1, 2, 3])
	game.resolution_visual_yield_active = false
	game.active_events = [null, null, null]
	game.card_presentation.clear()
	game.processing_resolution_stack = false
	game.game_has_ended = false
	game.game_flow_active = false
	for id in game.room_id_by_coord.values():
		var room = game.get_room_by_id(id)
		room.clear_instability()
		room.flipped = false
		room.activated_this_turn = false
	for p in game.players:
		p.evocations.clear()
		p.active_spells.clear()
		p.revealed_spells.clear()
		p.ready_spells.clear()
		p.quick_spell = null
		p.active_quests.clear()
		p.completed_quests.clear()
		p.available_cubes = 25
		p.starved_cubes = 0
		p.mage.damage_cubes.clear()
		p.mage.health = 12 if p.avatar != null else 11
		p.mage.destiny_tokens.clear()
		p.mage.jinxes.clear()
		p.mage.infectio_tokens.clear()
		p.power = 10
		p.hand.clear()
		p.memories.clear()
		p.trophies.clear()
		locate(p.player_index, "black_rose")
	for deck in game.avatar.decks.values(): deck.clear()
	game.avatar.commands_used = game.avatar.command_limit()
	game.avatar.active_command = null
	game.stored_evocation_owner_cubes.clear()
	game.black_rose_power = 0
	game.get_node("EventBoard").black_rose_cube_count = 30
	choices.clear()
	preferred.clear()

func drive():
	for i in 700:
		if not game.card_presentation.is_empty(): game.dismiss_card_presentation()
		if game.waiting_for_player_input:
			var request: Dictionary = game.pending_input.duplicate()
			choices.append(request)
			if request.type == "effect_choice":
				var options: Array = request.board_options if request.get("board_only", false) else request.options
				var token: String = str(preferred.get(str(request.context_key), options[0].token))
				expect(game.submit_effect_choice(int(request.player_index), token), "Choice accepted: " + str(request.context_key))
			elif request.type == "trigger_decision":
				expect(game.submit_trigger_decision(int(request.player_index), int(request.options[0].queue_index)), "Trigger accepted")
			else:
				expect(false, "Unexpected input " + str(request))
				return
		else: game.process_resolution_stack()
		await process_frame
		if game.resolution_stack.is_empty() and not game.waiting_for_player_input and not game.trigger_window_active: return
	expect(false, "Stalled stack " + str(game.resolution_stack))

func section(id: String, index: int = 0):
	var card: SpellCardState = cards["possessed_" + id]
	game.queue_resolution({"type": "avatar_section", "card": card,
		"section": card.avatar_command.sections[index], "context": {}, "stage": "target"})
	await drive()

func event_card(id: String):
	return game.event_database.events["avatar_" + id]

func event_effect(id: String):
	game.event_effect_resolver.resolve_event(event_card(id), {"game": game})
	await drive()

func arm(id: String):
	game.avatar.commands_used = 0
	game.avatar.active_deck().append(cards["possessed_" + id])

func hand(id: int, count: int):
	for i in count: game.players[id].hand.append(game.clone_spell_card(game.spell_database.spells.tearing))

func combat_event(context: Dictionary):
	var event := GameEvent.new("spell_effect_about_to_resolve")
	event.source_player_index = 0
	event.target_player_index = AVATAR
	event.target_model_type = "mage"
	event.set_meta("source_spell_type", "combat")
	event.set_meta("affected_player_indices", [AVATAR])
	event.set_meta("source_spell_context", context)
	game.process_game_event(event)
	await drive()

func spell_damage():
	game.active_effect_context = {"game":game, "caster_id":0, "spell_type":"combat", "spell_id":"tearing", "target_player_index":AVATAR}
	game.deal_damage(0, AVATAR, 4, "spell")
	game.active_effect_context = {}
	await drive()

func run():
	game = load("res://game.tscn").instantiate()
	game.player_count = 4
	game.game_seed = 182026
	game.enable_beta_hud = false
	game.run_tests_on_ready = true
	game.auto_start_game_flow = false
	game.beta_force_fullscreen = false
	game.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	root.add_child(game)
	for i in 4: await process_frame
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card

	reset_case()
	damage(0, [1, 1, -1, 2])
	await section("corrupted_ray")
	expect(game.players[0].mage.damage_cubes == [1, 1, -1, -1, -1, -1], "Corrupted Ray: damage then rightmost opponent conversion")
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1], "Unstable banner places before spell")
	expect(game.players[2].available_cubes == 25, "Conversion returns displaced cube")

	reset_case()
	damage(0, [1, -1, 2])
	await section("poisoned_thorns")
	expect(game.players[0].mage.damage_cubes == [-1, -1, -1], "Poisoned Thorns converts two, skipping existing BR cubes")
	expect(game.players[1].mage.get_damage() == 0, "Conversion does not create Damage")

	reset_case()
	damage(AVATAR, [0, 1, 1])
	preferred["heal_owner"] = "heal:stop"
	await section("sap_of_the_black_rose")
	expect(game.players[AVATAR].mage.get_damage() == 3 and game.black_rose_power == 2, "Sap: Crown may heal zero and gain 2 Power")
	expect(choices.size() == 1 and choices[0].player_index == 0, "Optional heal is chosen by Crown")

	reset_case()
	damage(AVATAR, [0, 1, 1])
	preferred["heal_owner"] = "heal:1"
	await section("energy_of_the_rose")
	expect(game.players[AVATAR].mage.damage_cubes == [0], "Energy: Crown chooses healing colors")
	expect(game.black_rose_power == 0, "Energy: no Power when healed")
	reset_case()
	await section("energy_of_the_rose")
	expect(game.black_rose_power == 1, "Energy: 1 Power if no Damage healed")

	reset_case()
	game.active_events[1] = event_card("thorny_corruption")
	game.place_instability(0, "arena", 2)
	await drive()
	expect(game.get_room_by_id("arena").instability_cubes == [0, -1], "Thorny Corruption converts newly placed rightmost cube in affected Room")
	game.place_instability(0, "garden", 1)
	await drive()
	expect(game.get_room_by_id("garden").instability_cubes == [0], "Thorny Corruption ignores single cube")

	reset_case()
	game.active_events[1] = event_card("divinatory_secrets")
	game.activate_room(0, "observatory", false, {"avatar_no_room_effect":true})
	await drive()
	expect(game.players[0].power == 11 and game.players[0].mage.damage_cubes == [-1], "Divinatory Secrets: activation grants Power then BR Damage")
	game.activate_room(AVATAR, "sanctuary", false, {"avatar_no_room_effect":true})
	await drive()
	expect(game.black_rose_power == 0 and game.players[AVATAR].mage.get_damage() == 0, "Room event excludes Avatar")

	reset_case()
	locate(AVATAR, "garden")
	await event_effect("traces_of_texture")
	expect(game.get_room_by_id("garden").instability_cubes == [-1, -1], "Traces: green Room places 2")
	locate(AVATAR, "throne")
	await event_effect("traces_of_texture")
	expect(game.get_room_by_id("throne").instability_cubes.is_empty(), "Throne symbol is not a purple Room")
	locate(AVATAR, "arena")
	await event_effect("remnants_of_magic")
	expect(game.get_room_by_id("arena").instability_cubes == [-1, -1], "Remnants: red Room places 2")
	locate(AVATAR, "black_rose")
	await event_effect("magic_of_the_rose")
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1, -1], "Magic Rose: within range places 2 in BR")

	reset_case()
	damage(0, [-1, 1, 2])
	damage(1, [0, 2])
	await event_effect("illness")
	expect(game.players[0].mage.damage_cubes == [-1, 1, -1], "Illness converts only Mage already carrying BR Damage")
	expect(game.players[1].mage.damage_cubes == [0, 2], "Illness excludes Mage without BR Damage")
	await event_effect("sorrow")
	expect(game.players[0].power == 9 and game.players[1].power == 10, "Sorrow loses Power only with BR Damage")

	reset_case()
	game.black_rose_power = 3
	game.players[0].power = 2
	game.players[1].power = 3
	game.players[2].power = 4
	await event_effect("singing_victory_again")
	expect([game.players[0].power, game.players[1].power, game.players[2].power] == [3,3,3], "Singing Victory compares each Mage with BR")
	await event_effect("crown_of_thorns")
	expect(game.players[0].power == 4 and game.players[0].mage.get_damage() == 2, "Crown of Thorns applies to Crown owner")
	await event_effect("pledge")
	expect(game.players[0].mage.get_damage() == 4 and game.players[1].mage.get_damage() == 2 and game.players[AVATAR].mage.get_damage() == 0, "Pledge damages nearby Mages but not Avatar")

	reset_case()
	arm("energy_of_the_rose")
	await spell_damage()
	expect(game.players[AVATAR].mage.get_damage() == 1, "Energy Protection ignores 3 of 4 Damage")
	expect(game.get_room_by_id("black_rose").instability_cubes.size() == 3, "Energy Protection places actual ignored amount")
	expect(game.avatar.commands_used == 1 and game.players[AVATAR].memories.size() == 1, "Reaction consumes one Command")
	expect(game.black_rose_power == 0, "Reaction does not execute printed Spell side")

	reset_case()
	arm("sap_of_the_black_rose")
	await spell_damage()
	expect(game.players[AVATAR].mage.get_damage() == 1 and game.players[0].mage.get_damage() == 3, "Sap Protection retaliates actual ignored Damage")

	reset_case()
	arm("revenge_of_the_thorn")
	await spell_damage()
	expect(game.black_rose_trophies == [0], "Revenge reaction awards Trophy of attacker")
	expect(game.players[AVATAR].mage.get_damage() == 4, "Revenge reaction does not ignore Damage")

	reset_case()
	arm("energy_of_the_rose")
	game.avatar.commands_used = 3
	await spell_damage()
	expect(game.players[AVATAR].mage.get_damage() == 4 and game.players[AVATAR].memories.is_empty(), "No reaction after Command limit")

	reset_case()
	game.active_effect_context = {}
	game.deal_damage(-1, AVATAR, 3, "spell")
	await drive()
	expect(game.players[AVATAR].mage.get_damage() == 0, "Avatar immune to BR Damage")
	game.deal_damage(0, AVATAR, 3, "event")
	await drive()
	expect(game.players[AVATAR].mage.get_damage() == 0, "Avatar ignores Event damage")

	reset_case()
	arm("revenge_embodied")
	var incoming := {"ignored_spell_players":[]}
	await combat_event(incoming)
	expect(AVATAR in incoming.ignored_spell_players, "Revenge Embodied ignores incoming Combat Effect")
	expect(game.players[0].mage.damage_cubes == [-1,-1], "Revenge Embodied retaliates 2")

	reset_case()
	arm("dark_hammer")
	damage(0, [1,2])
	await combat_event({})
	expect(game.players[0].mage.damage_cubes == [-1,-1,-1,-1], "Dark Hammer reaction damages and converts attacker")

	reset_case()
	arm("explosion_of_dark_petals")
	await spell_damage()
	expect(game.players[AVATAR].mage.get_damage() == 2, "Dark Petals Protection ignores 2")
	for i in AVATAR: expect(game.players[i].mage.get_damage() == 2, "Dark Petals Protection damages Models within 1, P%d" % i)

	# All targeted Combat sections, with enough health to inspect conversions.
	for entry in [["corrupted_spear",0,2,1],["dark_blade",0,1,1],["revenge_of_the_thorn",1,1,2],["revenge_embodied",1,2,2],["dark_hammer",1,2,1]]:
		reset_case()
		damage(0, [1,1,1])
		await section(entry[0], entry[1])
		expect(game.players[0].mage.get_damage() == 3 + int(entry[2]), entry[0] + " deals exact Damage")
		expect(game.players[0].mage.get_damage_from(-1) == int(entry[2]) + int(entry[3]), entry[0] + " converts exact Damage")

	reset_case()
	await section("dark_hammer", 1)
	expect(game.players[0].power == 9, "Dark Hammer: missing conversion costs target 1 Power")
	reset_case()
	await section("revenge_of_the_thorn", 1)
	expect(game.players[0].power == 8, "Revenge Thorn: missing conversions cost 2 Power")

	for id in ["incendiary_ball", "blaze", "dark_fire"]:
		reset_case()
		var enemy = game.summon_evocation(0, "colossus", "black_rose")
		var own = game.summon_evocation(AVATAR, "colossus", "black_rose")
		await drive()
		await section(id)
		for i in AVATAR: expect(game.players[i].mage.damage_cubes == [-1,-1,-1], id + " area damage P%d" % i)
		expect(enemy.damage_cubes == [-1,-1,-1] and own.get_damage() == 0, id + " uses BR cubes and respects own Evocation immunity")
		expect(game.get_room_by_id("black_rose").instability_cubes.size() == (0 if id == "incendiary_ball" else 1), id + " places printed instability")

	for id in ["unstable_thorns", "explosion_of_thorns", "explosion_of_dark_petals"]:
		reset_case()
		await section(id)
		for i in AVATAR: expect(game.players[i].mage.get_damage() == (2 if id == "explosion_of_dark_petals" else 1), id + " affects each Mage")

	reset_case()
	# A killed Mage's BR cubes must not be reused on another target within
	# the same printed sentence. Highest BR Damage is assigned first.
	damage(0, [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1])
	game.get_node("EventBoard").black_rose_cube_count = 1
	await section("unstable_thorns") # banner would consume the last cube
	expect(not game.players[0].mage.in_cell, "Instability banner precedes Damage and consumes available cube")
	reset_case()
	damage(0, [-1,-1,-1,-1,-1,-1,-1,-1,-1,-1])
	game.get_node("EventBoard").black_rose_cube_count = 1
	await section("incendiary_ball")
	expect(game.players[0].mage.in_cell, "First area target is defeated")
	expect(game.players[1].mage.get_damage() == 0 and game.players[2].mage.get_damage() == 0, "Defeat does not recycle cubes halfway through area Damage")

	reset_case()
	hand(0, 2)
	var ev = game.summon_evocation(0, "cadaver", "black_rose")
	await drive()
	await section("frost_spear", 1)
	expect(game.players[0].mage.get_damage() == 3 and not game.is_evocation_in_play(ev), "Frost Spear damages and removes eligible owned Evocation")

	reset_case()
	hand(0, 1)
	await section("freeze_soil", 1)
	expect(game.players[0].hand.is_empty() and game.players[0].memories.size() == 1 and game.players[0].power == 9, "Freeze Soil discards available Spell and loses Power for missing second")
	reset_case()
	hand(0, 2)
	game.summon_evocation(0, "cadaver", "black_rose")
	game.summon_evocation(0, "cadaver", "black_rose")
	await drive()
	await section("thorns_of_frost", 1)
	expect(game.players[0].hand.is_empty() and game.players[0].evocations.is_empty(), "Thorns of Frost removes one eligible Evocation per discarded Spell")
	reset_case()
	for i in AVATAR: hand(i, 2)
	await section("manuscript_on_deceptions", 1)
	for i in AVATAR: expect(game.players[i].hand.is_empty() and game.players[i].memories.size() == 2, "Manuscript discards 2 per Mage P%d" % i)

	for id in ["book_of_nature", "technomancy_book"]:
		reset_case()
		locate(AVATAR, "garden")
		game.get_room_by_id("garden").flipped = true
		await section(id, 1)
		expect(game.players[AVATAR].evocations.size() == 2, id + " summons 2 Cadavers")
		expect(game.get_room_by_id("garden").activated_this_turn, id + " activates Room without ordinary effect")
		await section(id, 1)
		expect(game.players[AVATAR].evocations.size() == 2, id + " grants nothing when Room already activated")

	for id in ["tales_of_destruction", "conspirators_study", "research_on_fire"]:
		reset_case()
		await section(id, 1)
		expect(game.players[AVATAR].completed_quests.size() == 1 and game.players[AVATAR].completed_quests[0].is_solved(), id + " draws and solves Quest")
		expect(game.black_rose_power == game.players[AVATAR].completed_quests[0].get_power_reward(), id + " gains only printed Quest Power")

	reset_case()
	await section("tap_into_the_black_rose", 1)
	expect(game.black_rose_power == 2, "Tap grants 2 Power after successful activation")
	reset_case()
	await section("release_energy", 1)
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1,-1], "Release Energy places 2 in BR")
	reset_case()
	locate(AVATAR, "arena")
	game.place_instability(0, "arena", 2)
	await drive()
	await section("release_force", 1)
	expect(game.get_room_by_id("arena").instability_cubes == [0,-1], "Release Force converts rightmost in another Room")

	for id in ["tomb_reinforcements", "infernal_reinforcements", "abyssal_reinforcements"]:
		reset_case()
		await section(id)
		expect(game.players[AVATAR].evocations.size() == (2 if id == "infernal_reinforcements" else 1), id + " summons printed creatures")
		await section(id, 1)
		expect(game.players[0].mage.get_damage() == (2 if id == "infernal_reinforcements" else 3), id + " activates one Evocation using Mage priority")

	print("AVATAR RULES: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
