extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(10):
		await process_frame
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.room_id = game.player_entrance_room_ids[0]
	var target: String = game._beta_adjacent_room_ids(player.mage.room_id)[0]
	var succubus = game.summon_evocation(1, "succubus", target)
	var durable := EvocationState.new("test_target", "Damage counter", "beast", 6, 1, 1, 1)
	durable.room_id = target
	game.players[1].add_evocation(durable)
	player.revealed_spells.append(RevealedSpellState.new(game.spell_database.spells["deflagrate"], true))
	player.revealed_spells.append(RevealedSpellState.new(game.spell_database.spells["viatorium_spagyricum"], true))
	var enhanced: bool = game.can_apply_enhancement(0, ["water", "water"])
	player.quick_spell = ReadySpellState.new(game.spell_database.spells["azoth_bomb"], false)
	game.cast_quick_spell(0)
	for option in game.pending_input.get("options", []):
		if option.get("room_id") == target:
			game.submit_effect_choice(0, [option.token])
			break
	var passed: bool = enhanced and not game.is_evocation_in_play(succubus) and durable.get_damage() == 4
	game.finalize_evocation_removal(durable)
	var unenhanced_target = game.summon_evocation(1, "succubus", target)
	player.revealed_spells.clear()
	player.revealed_spells.append(RevealedSpellState.new(game.spell_database.spells["deflagrate"], true))
	player.quick_spell = ReadySpellState.new(game.spell_database.spells["azoth_bomb"], false)
	game.cast_quick_spell(0, {"target_room_id": target})
	passed = passed and game.is_evocation_in_play(unenhanced_target) and unenhanced_target.get_damage() == 2
	print("AZOTH BOMB PLAYTEST: ", "PASS" if passed else "FAIL", " | two Water: 4 damage; one Water: 2 damage")
	quit(0 if passed else 1)
