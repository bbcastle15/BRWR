extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(10):
		await process_frame
	var player = game.players[0]
	player.mage.in_cell = false
	player.mage.room_id = game.player_entrance_room_ids[0]
	var earth: SpellCardState = game.spell_database.spells["fountain_of_the_three"]
	player.revealed_spells.append(RevealedSpellState.new(earth, false))
	var spell: SpellCardState = game.spell_database.spells["liquid_fire"]
	player.quick_spell = ReadySpellState.new(spell, true)
	game.cast_quick_spell(0)
	# Resolve the base summon-room choice before reaching the Enhancement.
	if game.waiting_for_player_input and game.pending_input.get("choice_kind") != "evocation_activation_plan":
		game.submit_effect_choice(0, [game.pending_input.options[0].token])
	var passed: bool = game.waiting_for_player_input and game.pending_input.get("choice_kind") == "evocation_activation_plan"
	if passed:
		var token: String = ""
		var destination: String = ""
		for option in game.pending_input.options:
			var plan: Dictionary = game.pending_effect_choice_values[option.token]
			if plan.get("evocation_attack_timing") == "none" and plan.get("evocation_move_room_ids", []).size() == 3:
				token = option.token
				destination = str(plan.evocation_move_room_ids[-1])
				break
		passed = token != "" and game.submit_effect_choice(0, [token])
		passed = passed and player.evocations.size() == 1 and player.evocations[0].room_id == destination
		passed = passed and player.evocations[0].speed == 2 and player.evocations[0].strength == 2
		for normal_plan in game._beta_evocation_activation_plans(player.evocations[0], 0):
			passed = passed and normal_plan.path.size() <= 2
	print("LIQUID FIRE DARK PLAYTEST: ", "PASS" if passed else "FAIL: enhancement did not offer/execute an activation plan")
	quit(0 if passed else 1)
