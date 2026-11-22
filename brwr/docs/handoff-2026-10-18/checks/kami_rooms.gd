extends "res://docs/handoff-2026-10-18/checks/playtest.gd"

const IDS := ["cherry_blossom_garden", "kami_throne_room", "oni_sacrificial_altar", "satori_arena", "shinto_sanctuary", "spiritual_black_rose_room", "wabi_sabi_mirrors_room"]

func install(id: String):
	var data: Dictionary = game.get_room(id)
	var room = game.get_room_by_id(str(data.replaces))
	room.setup_room(data)
	return room

func activate(id: String) -> void:
	var room = install(id)
	expect(game.activate_room(0, room.get_room_id()), "Activation queued: " + id)
	await drive()

func run() -> void:
	game = await make_game(4)
	for id in IDS:
		reset_case()
		var room = install(id)
		for path in ["res://assets/rooms/%s.png", "res://assets/rooms/rebuilt/%s.png", "res://assets/rooms/tokens/%s_available.png", "res://assets/rooms/tokens/%s_used.png"]:
			expect(ResourceLoader.exists(path % id) and load(path % id) is Texture2D, "Imported artwork: " + (path % id))
		expect(preload("res://room_variants.gd").allows(game.get_room(room.get_room_id()), room.room_data), "Named replacement: " + id)
		expect(not room.flipped and room.is_rebuilt() and room.has_activation_token() and room.can_activate(), "Intact initial face: " + id)
		expect(not room.get_effects().is_empty(), "Intact effect: " + id)
		room.mark_activated()
		expect(not room.can_activate() and room.can_activate(true), "Used token blocks a second ordinary activation: " + id)
		room.reset_activation()
		expect(room.can_activate(), "Turn reset restores token: " + id)
		var capacity: int = room.get_instability_resistance()
		expect(game.place_instability(0, room.get_room_id(), capacity) == capacity, "Initial face accepts Instability: " + id)
		var before: int = game.players[0].power
		var reward: int = int(game.calculate_room_completion_rewards(room).get(0, 0))
		expect(game.resolve_room_completion(room), "Full Room completes: " + id)
		expect(game.players[0].power == before + reward, "Completion reward once: " + id)
		expect(room.is_wrecked() and room.get_effects().is_empty() and not room.has_activation_token(), "Wrecked face has no effect or token: " + id)
		expect(not game.activate_room(0, room.get_room_id(), true, {"force_room_activation":true}), "Forced activation cannot restore wrecked effect: " + id)
		expect(game.place_instability(0, room.get_room_id(), 1) == 0, "Wrecked Room rejects cubes: " + id)
		expect(not game.resolve_room_completion(room), "No second completion: " + id)
		room.reset_activation()
		expect(not room.can_activate(true), "Turn reset never repairs a wrecked Room: " + id)
		var snapshot: Dictionary = preload("res://network_projection.gd").build(game, 1)
		room.flipped = false
		preload("res://network_projection.gd").apply(game, snapshot)
		expect(room.is_wrecked() and not room.has_activation_token(), "Web snapshot restores wrecked state: " + id)
	reset_case()
	var garden = install("cherry_blossom_garden")
	game.players[0].add_spell_to_grimoire(game.spell_database.get_spell("fortune_talisman"))
	var hand_before: int = game.players[0].hand.size()
	await activate("cherry_blossom_garden")
	expect(game.players[0].hand.size() == hand_before + 1, "Garden draws one Spell")
	reset_case()
	for id in ["fortune_talisman", "occult_tolls"]:
		game.players[0].add_spell_to_hand(game.spell_database.get_spell(id))
	await activate("kami_throne_room")
	expect(game.players[0].hand.is_empty() and game.players[0].power == 12, "Throne discards two and gains two Power")
	reset_case()
	game.players[0].add_spell_to_hand(game.spell_database.get_spell("fortune_talisman"))
	preferred["room_discard_cards"] = -1
	await activate("kami_throne_room")
	expect(game.players[0].hand.size() == 1 and game.players[0].power == 10, "Throne may discard zero")
	reset_case()
	game.place_instability(1, "arena", 1)
	chosen_room = "arena"
	await activate("oni_sacrificial_altar")
	expect(game.get_room_by_id("arena").instability_cubes == [0], "Oni converts one chosen Room cube")
	reset_case()
	preferred["room_choice"] = "mage:1"
	await activate("satori_arena")
	expect(game.players[1].mage.get_damage() == 1, "Satori inflicts one Damage before optional movement")
	reset_case()
	game.players[0].mage.damage_cubes.assign([1, 2, 3])
	var persistent = ongoing("susanoos_presence", true, 1, 2)
	var forgotten = ongoing("coming_of_the_kodama", false, 2)
	await activate("shinto_sanctuary")
	expect(game.players[0].mage.get_damage() == 1 and not persistent.active and forgotten.active, "Shinto heals two and removes only non-Forgotten Persistent")
	reset_case()
	for id in ["fortune_talisman", "occult_tolls"]:
		game.players[0].add_spell_to_hand(game.spell_database.get_spell(id))
	await activate("spiritual_black_rose_room")
	expect(game.players[0].power == 8 and game.players[0].hand.size() == 1 and game.players[0].hand[0].forgotten, "Spiritual Black Rose pays both costs and draws Forgotten")
	reset_case()
	game.players[0].power = 1
	await activate("spiritual_black_rose_room")
	expect(game.players[0].hand.is_empty(), "Spiritual Black Rose cannot draw without paying")
	for used in [false, true]:
		reset_case()
		garden = install("cherry_blossom_garden")
		garden.activated_this_turn = used
		chosen_room = "garden"
		await activate("wabi_sabi_mirrors_room")
		expect(game.players[0].hand.size() == 1 and garden.activated_this_turn == used, "Wabi-Sabi preserves target token state: " + str(used))
		expect(game.get_room_by_id("mirrors_room").activated_this_turn, "Wabi-Sabi consumes its own token")
		var request: Dictionary = decisions.filter(func(d): return d.get("context_key") == "room_remote_activation")[0]
		var options: Array = request.get("board_options", request.get("options", []))
		expect(not options.any(func(o): return o.get("room_id") in ["black_rose", "mirrors_room"]), "Wabi-Sabi excludes Black Rose and recursive self activation")
	reset_case()
	var core = game.get_room_by_id("crypt")
	expect(core.can_activate(), "Rebirth destroyed Room still activates repeatedly")
	core.mark_activated()
	expect(core.can_activate(), "Rebirth destroyed Room has no used token")
	core.flipped = true
	core.mark_activated()
	expect(not core.can_activate() and core.can_activate(true), "Rebirth rebuilt Room retains its activation limit")
	game.queue_free()
	await process_frame
	print("KAMI ROOMS: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
