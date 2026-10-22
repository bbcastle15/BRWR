extends "res://docs/handoff-2026-10-18/checks/avatar_flow.gd"

func protect(id: String, owner: int = 0, dark: bool = false):
	var active := ActiveSpellState.new(game.clone_spell_card(game.spell_database.spells[id]), owner, dark)
	game.players[owner].active_spells.append(active)
	return active

func run():
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card

	reset_case()
	damage(0, [1,1])
	var caput = protect("caput_draconis")
	await section("corrupted_ray")
	expect(not caput.active, "Caput triggers against Avatar Combat")
	expect(game.players[0].mage.damage_cubes == [1,1], "Caput ignores Damage and following conversion")
	await section("corrupted_ray")
	expect(game.players[0].mage.get_damage() == 4, "Protection does not leak to next Command")

	reset_case()
	protect("caput_draconis")
	await section("incendiary_ball")
	expect(game.players[0].mage.get_damage() == 0, "Caput ignores area Damage for its owner")
	expect(game.players[1].mage.get_damage() == 3 and game.players[2].mage.get_damage() == 3, "Area Protection leaves other targets affected")

	reset_case()
	var bone = protect("bone_shield")
	await section("corrupted_ray")
	expect(not bone.active, "Bone Shield triggers against Avatar non-Forgotten Spell")
	expect(game.players[0].mage.get_damage() == 0, "Bone Shield ignores Avatar Damage")
	expect(game.players[AVATAR].mage.get_damage() == 2, "Bone Shield retaliates against Avatar")

	reset_case()
	hand(0, 2)
	protect("caput_draconis")
	await section("freeze_soil", 1)
	expect(game.players[0].hand.size() == 2 and game.players[0].power == 10, "Caput ignores discard and missing-discard penalty")

	reset_case()
	damage(0, [1,1])
	var dark_caput = protect("caput_draconis", 0, true)
	arm("dark_hammer")
	await combat_event({"caster_id":0})
	expect(not dark_caput.active, "Dark Caput triggers against Avatar Protection reaction")
	expect(game.players[0].mage.damage_cubes == [1,1], "Dark Caput ignores retaliation and conversion")

	reset_case()
	var unused = protect("caput_draconis", 0, true)
	arm("energy_of_the_rose")
	game.deal_damage(0, AVATAR, 4, "spell")
	await drive()
	expect(unused.active, "Dark Caput stays armed when Avatar only prevents its own Damage")
	expect(game.players[AVATAR].mage.get_damage() == 1, "Avatar prevention still resolves with human Protection armed")

	reset_case()
	protect("bone_shield")
	await section("incendiary_ball")
	expect(game.players[0].mage.get_damage() == 0, "Bone Shield protects its owner against area Damage")
	expect(game.players[1].mage.get_damage() == 3 and game.players[2].mage.get_damage() == 3, "Bone Shield preserves other area targets")

	print("AVATAR HUMAN PROTECTIONS: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
