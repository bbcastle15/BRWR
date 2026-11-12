extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

func run() -> void:
	game = await make_game(4)
	check_setup()
	await check_plot()
	await check_courage()
	check_thorny_corruption()
	game.queue_free()
	await process_frame
	print("KAMI MAGES: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func check_setup() -> void:
	game.active_school_ids.assign(["agony", "alchemy"])
	game.create_school_libraries()
	var seats := [
		["abe_no_seimei", "onmyojis_plot", 10, 8, "agony"],
		["en_no_gyoja", "shoeis_courage", 11, 7, "alchemy"]
	]
	for i in seats.size():
		var row: Array = seats[i]
		var mage_id: String = row[0]
		var personal: String = row[1]
		var school: String = row[4]
		var options: Array = game._available_starting_mages(i)
		expect(options.any(func(o): return o.id == mage_id and o.personal_spell_id == personal and o.personal_spell_name == game.spell_database.get_spell(personal).card_name), "Setup offers the Mage with the named Personal Spell")
		var art: Texture2D = game.ReferenceCardPreview.card_texture("mages", mage_id)
		expect(art != null and art.get_size() == Vector2(1672, 941), "Mage Sheet loads at project resolution")
		expect(SpellArtResolver.get_texture(personal, "personal") != null, "Setup can display the Personal Spell")
		expect(game.assign_mage_to_player(i, mage_id), "Mage assignment succeeds")
		var player: PlayerState = game.players[i]
		expect([player.mage.health, player.hand_limit, player.mage.strength, player.mage.speed, player.max_active_quests] == [row[2], row[3], 2, 2, 2], "All five printed stats reach the player")
		player.school_id = school
		var start: Dictionary = game.get_starting_grimoire_options(school)[0]
		expect(game.build_starting_grimoire(i, school, start.id), "Starting Grimoire can be built")
		var cards: Array = player.grimoire + player.memories
		expect(cards.size() == 7 and cards.filter(func(card): return card.id == personal and card.personal).size() == 1, "Exactly one Personal Spell enters starting cards")
		expect(not game.school_libraries[school].any(func(card): return card.personal), "School Library contains no Personal Spell")

func check_plot() -> void:
	reset_case()
	await cast("onmyojis_plot", false)
	var owner: PlayerState = game.players[0]
	expect(owner.active_spells.size() == 1, "Casting Light registers its Persistent")
	if owner.active_spells.is_empty(): return
	var marker: ActiveSpellState = owner.active_spells[0]
	var center: String = game.room_for_persistent(marker)
	expect(center == "arena", "Light puts the Persistent in the targeted Room")
	var close_room := ""
	var far_room := ""
	for id in game.room_id_by_coord.values():
		if id == center: continue
		if game.is_room_within_effect_range(center, id, 1): close_room = id
		else: far_room = id
	expect(not close_room.is_empty() and not far_room.is_empty(), "The test Lodge contains near and distant Rooms")
	expect(not ForgottenPassives.can_convert_instability(game, center, 0, 1), "Caster's Instability is protected at the marker")
	expect(not ForgottenPassives.can_convert_instability(game, close_room, 0, -1), "Black Rose cannot convert a protected adjacent cube")
	expect(ForgottenPassives.can_convert_instability(game, far_room, 0, 1), "Caster's distant cubes are available")
	var room = game.get_room_by_id(center)
	room.clear_instability()
	for cube_owner in [0, 1, -1]:
		game.place_instability(cube_owner, center, 1)
	var enemy_context := {"game":game, "caster_id":2, "target_room_id":center}
	await effects([{"type":"convert_instability", "amount":3}], enemy_context)
	expect(room.instability_cubes == [0, 2, 2], "Real conversion preserves the protected color and cube order")
	expect(AvatarEffects.rightmost_conversion(game, room.instability_cubes, 3, room) == 2 and room.instability_cubes == [0, -1, -1], "Avatar conversion skips only the protected cube")
	var foreign := ongoing("onmyojis_plot", false, 1, -1, center)
	var destination = game.get_room_by_id("throne")
	destination.flipped = true
	destination.activated_this_turn = true
	game.crown_owner_id = 1
	chosen_room = "throne"
	await cast("onmyojis_plot", true)
	for choice in decisions:
		if choice.get("context_key") == "moving_persistent":
			expect(choice.options.size() == 1, "Only own room-assigned Persistents are offered")
		if choice.get("context_key") == "persistent_destination":
			var options: Array = choice.board_options if choice.get("board_only", false) else choice.options
			expect(not options.any(func(o): return o.room_id == center), "The token cannot move to its current Room")
	expect(marker.context.target_room_id == "throne" and foreign.context.target_room_id == center, "Dark moves only the selected owner's Persistent")
	expect(game.crown_owner_id == 0 and destination.activated_this_turn, "Dark activates an already used rebuilt Throne Room")
	expect(not ForgottenPassives.can_convert_instability(game, "throne", 0, 1), "Protection follows the token to the new Room")
	var projection: Dictionary = preload("res://network_projection.gd").build(game, 1)
	expect(projection.permanents.any(func(p): return p.owner == 0 and p.id == "onmyojis_plot" and p.room == "throne"), "The moved Persistent is visible in another client's table state")
	reset_case()
	owner.grimoire.assign([game.spell_database.get_spell("litany")])
	var power_before := owner.power
	await cast("onmyojis_plot", true)
	expect(owner.hand.size() == 1 and owner.power == power_before + 1 and decisions.is_empty(), "Dark draws and gains Power exactly once when no Persistent can move")

func check_courage() -> void:
	reset_case()
	var owner: PlayerState = game.players[1]
	owner.mage.damage_cubes.assign([0, 0, 0, 0])
	var strength := owner.get_mage_strength()
	await cast("shoeis_courage", false, 1)
	expect(owner.mage.get_damage() == 1 and owner.power == 11, "Light heals three and grants one Power")
	expect(owner.get_mage_strength() == strength, "No Strength bonus without Equipment")
	game.summon_evocation(1, "winged_sandals", "arena")
	expect(owner.get_mage_strength() == strength, "One Equipment is below the threshold")
	var second = game.summon_evocation(1, "talos_corset", "arena")
	expect(owner.get_mage_strength() == strength + 1, "Two Equipment grant one Strength")
	var third = game.summon_evocation(1, "trophy_belt", "arena")
	expect(owner.get_mage_strength() == strength + 1, "Three Equipment still grant exactly one Strength")
	game.finalize_evocation_removal(third)
	game.finalize_evocation_removal(second)
	expect(owner.get_mage_strength() == strength, "Losing Equipment recalculates Strength")
	reset_case()
	owner.available_physical_actions = 0
	# The published supply currently has no Forgotten Equipment. Mark one in this fixture.
	var definition: Dictionary = game.evocation_database.evocations["talos_corset"]
	definition["forgotten"] = true
	preferred["school_equipment"] = "equipment:winged_sandals"
	await cast("shoeis_courage", true, 1)
	var choices: Array = decisions.filter(func(d): return d.get("context_key") == "school_equipment")
	expect(choices.size() == 1 and not choices[0].options.any(func(o): return o.id == "talos_corset"), "Dark never offers a Forgotten Equipment")
	expect(owner.evocations.size() == 1 and owner.evocations[0].evocation_id == "winged_sandals", "Dark summons the chosen Equipment")
	expect(owner.available_physical_actions == 1, "Dark restores one Physical Action")
	for data in game.evocation_database.evocations.values():
		if data.archetype == "equipment": data["forgotten"] = true
	decisions.clear()
	await cast("shoeis_courage", true, 1)
	expect(owner.evocations.size() == 1 and owner.available_physical_actions == 2 and decisions.is_empty(), "Restore still resolves when no Equipment is available")

func check_thorny_corruption() -> void:
	reset_case()
	game.avatar_selection = {"id":"possessed", "difficulty":"apprentice"}
	AvatarRules.setup(game)
	var active := ongoing("onmyojis_plot", false, 0, -1, "arena")
	var room = game.get_room_by_id("arena")
	game.place_instability(0, "arena", 2)
	var activation := {"effect":{"type":"avatar_convert_new_instability"}, "room_id":"arena", "target":0}
	AvatarEvents.process(game, activation.duplicate(true))
	expect(room.instability_cubes == [0, 0], "Thorny Corruption cannot convert protected Instability")
	active.active = false
	AvatarEvents.process(game, activation.duplicate(true))
	expect(room.instability_cubes == [0, -1], "Thorny Corruption can convert again after the Persistent expires")
