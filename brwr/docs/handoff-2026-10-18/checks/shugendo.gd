extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

func run() -> void:
	game = await make_game(4)
	expect(game.is_school_complete("shugendo"), "School is available at setup")
	game.active_school_ids.assign(["shugendo"])
	game.create_school_libraries()
	expect(game.school_libraries.shugendo.size() == 36, "Library has three copies of twelve Spells")
	for id in ["gohei","kagura_suzu","kusanagi_no_tsurugi","mononoke","ofuda","omamori","shakujo"]:
		expect(game.ReferenceCardPreview.card_texture("evocations", id) != null, "Evocation artwork: " + id)
	for id in ["coming_of_the_kodama","image_of_amaterasu","image_of_tsukuyomi","mononokes_fury"]:
		expect(game.spell_database.get_spell(id).forgotten and SpellArtResolver.get_texture(id) != null, "Forgotten card: " + id)
	reset_case()
	game.players[0].available_physical_actions = 0
	for id in ["fortune_talisman","occult_tolls"]:
		game.players[0].add_spell_to_hand(game.spell_database.get_spell(id))
	await cast("spiritual_perfection", false)
	expect(game.players[0].available_physical_actions == 2, "Repeat resolves Restore twice")
	expect(game.players[0].hand.is_empty() and game.players[0].revealed_spells.size() == 1, "Repeat pays two cards and reveals once")
	reset_case()
	game.players[0].available_physical_actions = 0
	for id in ["fortune_talisman","occult_tolls"]:
		game.players[0].add_spell_to_hand(game.spell_database.get_spell(id))
	preferred["kami_repeat"] = -1
	await cast("spiritual_perfection", false)
	expect(game.players[0].available_physical_actions == 1 and game.players[0].hand.size() == 2, "Declining Repeat keeps the hand and resolves Restore once")
	reset_case()
	await cast("summoning_the_kami", true)
	expect(game.place_instability(-1, "arena", 1) == 0 and not ForgottenPassives.can_convert_instability(game,"arena",1,0), "Room ward prevents placement and conversion")
	reset_case()
	await cast("image_of_amaterasu", false)
	expect(game.players[0].evocations.any(func(ev): return ev.evocation_id == "kusanagi_no_tsurugi"), "Forgotten Equipment can be summoned")
	preferred["move_target_destination"] = "move_target:arena"
	preferred["druidic_attack"] = -1
	expect(EquipmentRules.perform(game, 0, "kusanagi_no_tsurugi", "solar_slash"), "Solar Slash is available as a Physical Action")
	await drive()
	expect(game.players[0].evocations[0].damage_cubes == [-1], "Solar Slash costs one Black Rose Damage on the Equipment")
	reset_case()
	await cast("coming_of_the_kodama", false)
	var wards: Array = game.players[0].active_spells[0].context.ward_rooms
	var remote = preload("res://network_projection.gd").build(game, 1)
	expect(remote.permanents.size() == 1 and remote.permanents[0].ward_slots.size() == 4, "Remote snapshot carries four wards attached to one Spell")
	expect(wards.size() == 4 and game.place_instability(1, wards[0], 1) == 0 and game.place_instability(0, wards[0], 1) == 1, "Kodama protects four different Rooms for its owner")
	reset_case()
	await cast("coming_of_the_kodama", true)
	expect(decisions.filter(func(d): return d.get("context_key") == "kami_repeat").size() == 5, "Free Repeat stops at five")
	reset_case()
	await cast("mononokes_fury", true)
	var branches := decisions.filter(func(d): return d.get("context_key") == "kami_fury")
	expect(branches.size() == 6 and branches[3].options.size() == 2, "Fury offers six Effects and retires the first branch after three uses")
	reset_case()
	await cast("susanoos_presence", true)
	locate(1, "garden")
	game.place_mage_in_room_direct(1, "arena")
	await drive()
	expect(game.players[1].mage.get_damage() == 3, "Susanoo damages the entering Mage once")
	reset_case()
	await cast("tenjins_teaching", true)
	game.place_instability(-1, "arena", 1)
	await effects([{"type":"convert_instability","amount":1}], {"game":game, "caster_id":1,"target_room_id":"arena","spell_target_type":"room"})
	expect(game.players[1].mage.get_damage() == 2, "Tenjin damages the marked converter")
	reset_case()
	var spirit = game.summon_evocation(0, "mononoke", "black_rose")
	expect(not game._spell_evocation_target_options(1, {"range":"*"}, false).any(func(o): return o.value.evocation == spirit), "Mononoke cannot be targeted from Arena")
	locate(1, "black_rose")
	expect(game._spell_evocation_target_options(1, {"range":"*"}, false).any(func(o): return o.value.evocation == spirit), "Mononoke can be targeted from the Black Rose Room")
	reset_case()
	for i in 4: locate(i, "black_rose")
	preferred["attack_target"] = "room:black_rose"
	await cast("mononokes_fury", false)
	expect(game.players[1].mage.get_damage() == 5 and game.players[2].mage.get_damage() == 5, "Summoned Mononoke attacks the Room with +2 Strength at range zero")
	reset_case()
	game.summon_evocation(0, "omamori", "arena")
	game.deal_damage(1, 0, 3, "spell")
	await drive()
	expect(game.players[0].mage.get_damage() == 2 and game.players[0].evocations[0].get_damage() == 1, "Omamori redirects exactly one Damage")
	for card in game.spell_database.get_school_spells("shugendo"):
		for dark in [false, true]:
			reset_case()
			preferred["kami_repeat"] = -1
			await cast(card.id, dark)
			expect(game.players[0].revealed_spells.size() == 1, card.card_name + " resolves and reveals")
	game.queue_free()
	await process_frame
	print("SHUGENDO: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
