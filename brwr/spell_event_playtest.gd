extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

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
	player.quick_spell = ReadySpellState.new(game.spell_database.spells["cross_and_delight"], false)
	game.cast_quick_spell(0, {"target_room_id": player.mage.room_id})
	check(game.pending_input.get("choice_kind") == "evocation_activation_plan", "Cross and Delight must offer an activation")
	if game.pending_input.get("choice_kind") == "evocation_activation_plan":
		var selected := ""
		var destination := ""
		for option in game.pending_input.options:
			var plan: Dictionary = game.pending_effect_choice_values[option.token]
			if plan.get("evocation_attack_timing") == "none" and not plan.get("evocation_move_room_ids", []).is_empty():
				selected = option.token
				destination = plan.evocation_move_room_ids[-1]
				break
		check(selected != "" and game.submit_effect_choice(0, [selected]), "Cross activation choice must commit")
		check(player.evocations[0].room_id == destination, "Summoned Succubus must move")
	check(game.resolution_stack.is_empty(), "Cross must finish resolution")
	var construct_room: String = game.player_entrance_room_ids[1]
	var construct = game.summon_evocation(0, "nigredo", construct_room)
	var soul: Dictionary = game.spell_database.spells["soul_transfer"].get_side(false)
	var options: Array = game._spell_room_target_options(0, soul)
	check(options.size() == 1 and options[0].room_id == construct_room, "Soul Transfer must offer only the own Construct's room")
	check(not game._spell_room_target_allowed(0, soul, player.mage.room_id), "An unrelated room must be illegal")
	var ready := ReadySpellState.new(game.spell_database.spells["soul_transfer"], false)
	player.quick_spell = ready
	game.cast_quick_spell(0, {"target_room_id": player.mage.room_id})
	check(player.quick_spell == ready, "Illegal Soul Transfer target must not consume the card")
	check(not game._spell_room_target_allowed(0, soul, "black_rose"), "Excluded room must remain illegal")
	player.evocations.erase(construct)
	check(game._spell_room_target_options(0, soul).is_empty(), "Removed Construct must not remain a target source")
	game.players[1].evocations.append(construct)
	construct.owner_id = 1
	construct.controller_id = 1
	check(game._spell_room_target_options(0, soul).size() == 1, "Soul Transfer Light permits any Construct, as printed")
	game.players[1].evocations.clear()
	# Force the exact Clean-up -> instant event path from the reported stack.
	game.game_flow_active = true
	game.starting_setup_complete = true
	for p in game.players:
		p.power = 3
	var event: EventCardState = game.event_database.events["a_hard_lesson"]
	game.event_decks[game.current_moon] = [event]
	for spell in game.spell_database.spells.values():
		if spell.get_side(false).get("type") == "trap":
			player.active_spells.append(ActiveSpellState.new(spell, 0, false))
			break
	check(game.resolve_cleanup_phase(), "Clean-up must start")
	check(game.pending_input.get("type") == "cleanup_active_spells", "Fixture must require a cleanup choice")
	check(game.submit_cleanup_active_spells(0, []), "Cleanup choice must succeed while event waits for input")
	var placed := 0
	while game.pending_input.get("choice_kind") == "event_cell_destination" and placed < game.players.size():
		var owner: int = game.pending_input.player_index
		check(game.players[owner].power == 2, "Power loss must be applied exactly once")
		check(not game.submit_effect_choice(owner, ["room:invalid"]), "Invalid event choice must be rejected safely")
		var choice: String = game.pending_input.options[0].token
		var destination: String = game.pending_effect_choice_values[choice]
		check(game.submit_effect_choice(owner, [choice]), "Event placement must resume")
		check(game.players[owner].mage.room_id == destination, "Event must place the selected Mage")
		placed += 1
	check(placed == game.players.size(), "Every Mage must receive a destination choice")
	check(game.event_discard.count(event) == 1, "Instant event must be discarded exactly once")
	check(game.resolution_stack.is_empty(), "Event resolution must finish")
	check(game.waiting_for_player_input and game.pending_input.get("choice_kind") != "event_cell_destination", "Game must advance to the next interaction")
	print("SPELL / EVENT PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
