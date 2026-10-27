extends "res://docs/handoff-2026-10-18/checks/avatar_flow.gd"

func run():
	game = await create_game()
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	reset_case()
	var target := ""
	var origin := ""
	# Fix the color distribution to isolate Speed from destination ties.
	for id in game.room_id_by_coord.values():
		game.get_room_by_id(id).room_data = game.get_room_by_id(id).room_data.duplicate(true)
		game.get_room_by_id(id).room_data["color"] = "red"
	for a in game.room_id_by_coord.values():
		for b in game.room_id_by_coord.values():
			if AvatarRules.distance(game, a, b) == 2:
				origin = a
				target = b
				break
		if not target.is_empty(): break
	game.get_room_by_id(target).room_data["color"] = "grey"
	locate(AVATAR, origin)
	expect(cards.possessed_book_of_nature.avatar_command.sections[0].effects[0].color == "grey", "Book of Nature moves toward grey, as printed")
	game.queue_resolution({"type":"avatar_section", "card":cards.possessed_corrupted_ray,
		"section":cards.possessed_book_of_nature.avatar_command.sections[0], "context":{}, "stage":"target"})
	await drive()
	expect(game.players[AVATAR].get_mage_speed() == 2, "Possessed has Speed 2")
	expect(game.players[AVATAR].mage.room_id == target, "Speed 2 reaches the only grey Room two steps away")
	for request in choices:
		expect(request.player_index == game.crown_owner_id, "Only Crown chooses tied paths")
	reset_case()
	for id in game.room_id_by_coord.values(): game.get_room_by_id(id).room_data["color"] = "red"
	var adjacent: Array = game._beta_adjacent_room_ids("black_rose")
	game.get_room_by_id(adjacent[0]).room_data["color"] = "grey"
	game.get_room_by_id(adjacent[1]).room_data["color"] = "grey"
	game.queue_resolution({"type":"avatar_section", "card":cards.possessed_book_of_nature,
		"section":cards.possessed_book_of_nature.avatar_command.sections[0], "context":{}, "stage":"target"})
	await drive()
	expect(not choices.is_empty(), "Equally near grey Rooms require a Crown decision")
	for request in choices:
		expect(request.player_index == game.crown_owner_id and "Choice of the Crown" in request.prompt, "Movement choice explicitly belongs to Crown")
		expect(request.context_key == "destination", "Unique shortest step needs no extra choice")
	expect(game.players[AVATAR].mage.room_id in [adjacent[0],adjacent[1]], "Movement stops upon reaching chosen grey Room")
	reset_case()
	for id in game.room_id_by_coord.values(): game.get_room_by_id(id).room_data["color"] = "red"
	var yellow: String = game._beta_adjacent_room_ids("black_rose")[0]
	game.get_room_by_id(yellow).room_data["color"] = "yellow"
	locate(1, "garden")
	locate(2, "garden")
	damage(0, [1])
	await command("corrupted_ray")
	expect(game.players[0].mage.get_damage() == 3, "Corrupted Ray deals two damage to selected Mage")
	expect(game.players[0].mage.damage_cubes == [-1,-1,-1], "Corrupted Ray converts damage, not Instability")
	expect(game.players[AVATAR].mage.room_id == yellow, "Corrupted Ray physical section moves toward yellow Room")
	for request in choices:
		expect(request.get("context_key", "") != "target_room_id", "Corrupted Ray spell does not target an unrelated Room")
	print("AVATAR MOVEMENT: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
