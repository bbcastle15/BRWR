extends SceneTree

var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(3): await process_frame

func choose(token: String) -> void:
	check(game.submit_beta_input(0, {"selection": [token]}), "Accept choice " + token)

func click_cube(token: String) -> void:
	for button in get_nodes_in_group("board_target_choices"):
		if button is Button and str(button.get_meta("choice_token", "")) == token:
			button.pressed.emit()
			await settle()
			check(game.beta_hud.generic_selection.has(token), "Clicked cube stays selected: " + token)
			return
	check(false, "Missing clickable cube: " + token)

func confirm_cubes() -> void:
	for button in game.beta_hud.decision_actions.get_children():
		if button is Button and button.text.begins_with("Confirm"):
			check(not button.disabled, "Cube confirmation is enabled")
			button.pressed.emit()
			await settle()
			return
	check(false, "Missing cube confirmation")

func solve(id: String) -> QuestState:
	var quest := QuestState.new(game.quest_database.get_quest(id), 0)
	quest.completed = true
	quest.revealed = true
	game.players[0].completed_quests.append(quest)
	check(game.quest_manager.solve_quest(game, 0, quest), "Start Quest " + id)
	# Quest effects begin after the public card presentation finishes.
	while not game.card_presentation.is_empty():
		await process_frame
	return quest

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Five fixes timed out"); quit(1))
	game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = true
	game.beta_force_fullscreen = false
	game.game_seed = 1232
	root.add_child(game)
	while game.beta_hud == null: await process_frame
	game.active_events.assign([null, null, null])
	var player = game.players[0]
	for entry in game.players:
		entry.mage.in_cell = false
		entry.mage.room_id = "forge"
		entry.mage.room_coord = game.room_id_to_coord("forge")

	# Exercise the same deferred cube buttons and confirmation as the UI.
	# A new Quest invalidates the table projection during the pending choice.
	player.active_quests.append(QuestState.new(game.quest_database.get_quest("warrior_wizard"), 0))
	game.players[1].mage.damage_cubes.assign([-1, 1, -1, 1])
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("albify"), true)
	check(game.cast_quick_spell(0, {"target_room_id": "forge"}), "Cast Albify Dark")
	check(game.pending_input.get("choice_kind") == "convert_damage_cubes", "Albify asks for damage cubes")
	await settle()
	await click_cube("damage:-1:0")
	game.refresh_all_player_boards()
	await click_cube("damage:1:0")
	await click_cube("damage:1:1")
	await confirm_cubes()
	check(game.players[1].mage.damage_cubes == [0, 0, -1, 0], "Albify converts selected cubes in place")
	check(game.resolution_stack.is_empty(), "Albify finishes after UI confirmation")
	check(player.active_quests[0].progress == 1, "Spell still progresses Warrior Wizard")
	player.active_quests.clear()

	# Enhancement damage comes first; conversion excludes the caster and its models.
	player.revealed_spells.append(RevealedSpellState.new(game.spell_database.get_spell("liquid_fire"), false))
	var own = game.summon_evocation(0, "nigredo", "forge")
	var enemy = game.summon_evocation(1, "nigredo", "forge")
	own.damage_cubes.assign([-1])
	enemy.damage_cubes.assign([-1, 1])
	player.mage.damage_cubes.assign([-1])
	game.players[1].mage.damage_cubes.assign([-1, -1, 1, 1])
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("albify"), true)
	check(game.cast_quick_spell(0, {"target_room_id": "forge"}), "Cast enhanced Albify")
	check(game.players[1].mage.damage_cubes == [-1, -1, 1, 1, 0], "Enhancement damages before conversion")
	check(game.submit_effect_choice(0, ["damage:-1:1", "damage:1:0", "damage:1:1"]), "Select enhanced Albify conversion")
	check(game.players[1].mage.damage_cubes == [-1, 0, 0, 0, 0], "Enhancement plus three converted cubes")
	check(enemy.damage_cubes == [0, 0, 0], "Area conversion includes opposing Evocation")
	check(own.damage_cubes == [-1] and player.mage.damage_cubes == [-1], "Own models unaffected")

	# Health value is 4 even when a Nigredo has only 1 remaining Health.
	enemy.damage_cubes.assign([-1, -1, -1])
	var warrior_effect: Dictionary = game.quest_database.get_quest("warrior_wizard").effects[0]
	check(game._quest_evocation_choice_options(0, warrior_effect).is_empty(), "Warrior excludes damaged Health-4 Nigredos")
	var cadaver = game.summon_evocation(1, "cadaver", "garden")
	var warrior: QuestState = await solve("warrior_wizard")
	check(not game.is_evocation_in_play(cadaver), "Warrior removes eligible Health-2 Evocation")
	check(game.is_evocation_in_play(enemy), "Warrior preserves Health-4 Nigredo")
	check(game.pending_input.get("choice_kind") == "target_room", "Warrior proceeds to its independent Instability target")
	choose("room:forge")
	check(warrior.solved, "Warrior rewards and finishes")

	# Recovery and quest progress use only the active header Element.
	player.revealed_spells.clear()
	var fire := RevealedSpellState.new(game.spell_database.get_spell("liquid_fire"), true)
	var earth := RevealedSpellState.new(game.spell_database.get_spell("marbling"), false)
	var air := RevealedSpellState.new(game.spell_database.get_spell("purifying_aludel"), false)
	player.revealed_spells.assign([fire, earth, air])
	var earth_card = game.quest_database.get_quest("earth_tempest")
	check(not game.quest_manager._check_revealed_spell_elements(game, 0, earth_card.task), "Two real Elements plus an Enhancement requirement do not make three")
	var tempest: QuestState = await solve("earth_tempest")
	check(game.pending_input.get("choice_kind") == "revealed_spell", "Earth Tempest asks which card to recover")
	check(game.pending_input.options.size() == 2, "Only the two Air/Earth cards are eligible")
	check(not game.submit_effect_choice(0, ["revealed:0"]), "Cannot submit Fire as recovery choice")
	check(not game.effect_resolver.resolve_effect(earth_card.effects[0], {"game": game, "caster_id": 0, "resolver_kind": "quest", "selected_revealed_spell": fire}), "Resolver also rejects Fire")
	choose("revealed:1")
	check(player.hand.has(earth.spell) and player.revealed_spells.has(fire), "Recover correct card instance")
	choose("room:forge")
	check(tempest.solved, "Earth Tempest resolves its separate damage Effect")
	var required_elements: Array[String] = ["earth", "air"]
	check(game._quest_side_has_any_element({"element": "all"}, required_elements), "All-Elements remains a wildcard")

	# Two Constructs offer two Room clicks; empty legacy context is not a choice.
	game.finalize_evocation_removal(enemy)
	var second = game.summon_evocation(0, "nigredo", "garden")
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("soul_transfer"), false)
	check(game.cast_quick_spell(0, {"target_room_id": ""}), "Cast Soul Transfer with empty target context")
	check(game.pending_input.get("choice_kind") == "construct_room" and game.pending_input.options.size() == 2, "Soul offers both distinct Construct Rooms")
	check(get_nodes_in_group("lodge_room_choices").size() >= 2, "Soul destinations are clickable on Lodge")
	choose("room:garden")
	check(game.pending_input.get("choice_kind") == "room_effect_room_target", "Garden asks its own Effect target separately")
	check(game.pending_input.options.all(func(option): return game.is_room_within_effect_range("garden", option.room_id, 1)), "Activated Room supplies the effect origin")
	choose("room:garden")
	check(game.resolution_stack.is_empty(), "Soul and activated Room finish")
	game.finalize_evocation_removal(second)
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("soul_transfer"), false)
	game.cast_quick_spell(0)
	check(game.pending_input.get("choice_kind") == "construct_room" and game.pending_input.options.size() == 1, "Single Room is also explicitly confirmed")
	choose("room:forge")
	choose("room:forge")
	var invalid_ready := ReadySpellState.new(game.spell_database.get_spell("soul_transfer"), false)
	player.quick_spell = invalid_ready
	game.cast_quick_spell(0, {"target_room_id": "black_rose"})
	check(player.quick_spell == invalid_ready, "Illegal prefilled Room does not consume Soul Transfer")

	# Full optional Quest flow updates both authoritative location and tokens.
	game.finalize_evocation_removal(own)
	player.mage.room_id = "forge"
	player.mage.room_coord = game.room_id_to_coord("forge")
	game.players[1].mage.room_id = "garden"
	game.players[1].mage.room_coord = game.room_id_to_coord("garden")
	game.refresh_model_tokens()
	var illusion: QuestState = await solve("illusory_moon")
	choose("choice:yes")
	choose("room:crypt")
	check(illusion.solved, "Illusory Moon completes")
	check(player.mage.room_id == "garden" and game.players[1].mage.room_id == "crypt", "Illusory Moon places both Mages")
	check(game.mage_tokens[0].position.is_equal_approx(game.hex_to_pixel(game.room_id_to_coord("garden"))), "Caster token follows new Room")
	check(game.mage_tokens[1].position.is_equal_approx(game.hex_to_pixel(game.room_id_to_coord("crypt"))), "Target token follows new Room")
	check(game.resolution_stack.is_empty() and not game.waiting_for_player_input, "All reported flows finish")
	print("FIVE FIXES PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
