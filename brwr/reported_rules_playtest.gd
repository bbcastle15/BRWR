extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(8): await process_frame
	for player in game.players:
		player.mage.in_cell = false
		player.mage.room_id = "forge"
		player.mage.room_coord = game.room_id_to_coord("forge")
	var player = game.players[0]
	# Reference identity: a second copy counts, the currently played copy does not.
	var spell = game.clone_spell_card(game.spell_database.get_spell("fountain_of_the_three"))
	var duplicate = game.clone_spell_card(spell)
	player.revealed_spells.assign([RevealedSpellState.new(spell, false)])
	check(not game.can_apply_enhancement(0, ["earth"], spell), "A card cannot enhance itself")
	player.revealed_spells.append(RevealedSpellState.new(duplicate, false))
	check(game.can_apply_enhancement(0, ["earth"], spell), "Another physical copy must count")
	player.revealed_spells.clear()
	# Codex Arcanum p. 7: only the previously resolved side of OTHER cards.
	var two_sides := SpellCardState.new("sides", "Sides", "alchemy", {"element": "fire"}, {"element": "water"})
	player.revealed_spells.assign([RevealedSpellState.new(two_sides, false)])
	check(game.can_apply_enhancement(0, ["fire"]), "Active Light element must count")
	check(not game.can_apply_enhancement(0, ["water"]), "Inactive Dark element must not count")
	player.revealed_spells[0].use_dark_side = true
	check(game.can_apply_enhancement(0, ["water"]) and not game.can_apply_enhancement(0, ["fire"]), "Only active Dark element must count")
	player.revealed_spells.clear()
	var current := SpellCardState.new("test", "Test", "alchemy", {"type": "combat", "target": "special", "element": "earth", "effects": [], "enhancement": {"requires": ["earth"], "effects": [{"type": "gain_power", "amount": 2}]}}, {})
	player.quick_spell = ReadySpellState.new(current, false)
	var before: int = player.power
	game.cast_quick_spell(0)
	check(player.power == before, "Casting must not count its own element")
	# Growth survives phase dispatch and pays only when its Room color activates.
	game.current_phase = game.PHASE_ACTION
	var growth = game.event_database.get_event("growth")
	game.active_events.assign([growth, null, null])
	before = game.black_rose_power
	check(game.resolve_events_for_phase(game.PHASE_ACTION), "Growth must not block Action Phase")
	check(game.black_rose_power == before, "Growth must not pay at phase start")
	game.process_room_activation_resolution({"step": "after_effects", "player_index": 0, "room_id": "forge"})
	check(game.black_rose_power == before + 1, "Growth must pay on green Room activation")
	game.process_room_activation_resolution({"step": "after_effects", "player_index": 0, "room_id": "crypt"})
	check(game.black_rose_power == before + 1, "Growth must ignore other colors")
	game.active_events.assign([null, null, null])
	game.place_instability(-1, "forge", 1)
	check(game.get_room_by_id("forge").instability_cube_nodes.size() == 1, "Black Rose instability needs a visible cube node")
	# Global spell: no Room selection; base hits Evocations, Enhancement hits Mages.
	var enemy = game.summon_evocation(1, "nigredo", "forge")
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("marbling"), false)
	game.cast_quick_spell(0)
	check(not game.waiting_for_player_input, "Marbling Light must not request a Room")
	check(enemy.get_damage() == 1, "Marbling Light must hit enemy Evocations globally")
	player.revealed_spells.assign([
		RevealedSpellState.new(game.clone_spell_card(game.spell_database.get_spell("liquid_fire")), false),
		RevealedSpellState.new(game.clone_spell_card(game.spell_database.get_spell("liquid_fire")), false)])
	game.players[1].mage.room_id = "crypt"
	player.quick_spell = ReadySpellState.new(game.clone_spell_card(game.spell_database.get_spell("marbling")), false)
	game.cast_quick_spell(0)
	check(game.players[1].mage.get_damage() == 1 and player.mage.get_damage() == 0, "Marbling Enhancement hits opposing Mages in other Rooms, respecting immunity")
	# Spell activation does not use the once-per-Evocation-Phase allowance.
	var own = game.summon_evocation(0, "nigredo", "forge")
	player.quick_spell = ReadySpellState.new(game.spell_database.get_spell("fountain_of_the_three"), true)
	game.cast_quick_spell(0, {"target_room_id": "forge", "fountain_choice": "activate_construct", "selected_evocation_to_activate": own, "evocation_attack_timing": "none", "evocation_move_room_ids": []})
	check(not game.waiting_for_player_input, "Fountain activation must finish")
	check(game.evocation_phase_activated.is_empty(), "Spell activation must not consume Phase activation")
	game.crown_owner_id = 0
	game.resolve_evocation_phase()
	check(game.pending_input.get("type") == "evocation_phase_activations", "Evocation Phase must offer an activation after Fountain")
	var seen := false
	for data in game.pending_input.get("evocations", []):
		if data.id == "nigredo": seen = true
	check(seen, "Nigredo must remain available in Evocation Phase")
	game.clear_player_input()
	# Three active Quests are legal until the Black Rose limit step.
	player.active_quests.clear()
	player.completed_quests.clear()
	var card := QuestCardState.new("test_quest", "Test Quest", 1, {}, [], 1, 2)
	game.quest_decks[1] = [card, card, card, card]
	game.current_moon = 1
	for i in range(3): game.quest_manager.draw_quest(game, 0)
	check(player.active_quests.size() == 3 and game.quest_manager.get_active_excess(game, 0) == 1, "Third Quest must be drawn; discard is deferred")
	for i in range(4):
		var solved := QuestState.new(card, 0)
		solved.solve()
		player.completed_quests.append(solved)
	check(game.quest_manager.get_completed_excess(game, 0) == 0, "Solved Quests never count toward the limit")
	var completed := QuestState.new(card, 0)
	completed.complete()
	player.completed_quests.append(completed)
	before = player.power
	check(game.quest_manager.solve_quest(game, 0, completed), "Completed Quest must resolve")
	check(completed.is_solved() and player.power == before + 2, "Quest reward must be assigned once")
	game.quest_manager.finalize_quest_solve(game, 0, completed)
	check(player.power == before + 2, "Resuming a Quest must not award twice")
	# Defeat rewards, trophies, health reset, and tied contributions.
	game.current_phase = game.PHASE_ACTION
	game.players[1].mage.damage_cubes.clear()
	before = player.power
	game.deal_damage(0, 1, game.players[1].mage.health)
	check(player.power == before + 5, "Sole damage contributor receives five Power")
	check(player.trophies == [1], "Last attacker receives the Trophy")
	check(game.players[1].mage.in_cell and game.players[1].mage.get_damage() == 0, "Defeat must reset Health and return to Cell")
	check(game.ranked_power_rewards({0: 5, 1: 5, -1: 1}, true) == {0: 3, 1: 3, -1: 2}, "Tied first contributors leave second reward for the next damage level")
	# All points are retained above 35; final bonuses are applied once.
	game.set_player_power(0, 38)
	game.set_player_power(1, 10)
	game.set_black_rose_power(0)
	game.crown_owner_id = 0
	check(game.check_end_game(), "Threshold must end the game")
	check(game.players[0].power == 47, "38 base + 4 Quests + 4 Trophies + 1 Crown")
	check(game.final_result.winner == 0, "Final winner must be computed")
	game.check_end_game()
	check(game.players[0].power == 47, "Final scoring must be idempotent")
	var replica = load("res://game.tscn").instantiate()
	replica.enable_beta_hud = false
	replica.auto_start_game_flow = false
	replica.network_client = true
	root.add_child(replica)
	for i in range(8): await process_frame
	load("res://network_projection.gd").apply(replica, load("res://network_projection.gd").build(game, 1))
	check(replica.final_result == game.final_result, "Online client must receive final results")
	# Exact score/Quest/Trophy ties are decided by the First Mage, through UI input.
	game.game_has_ended = false
	game.final_result.clear()
	game.black_rose_trophies.clear()
	for p in game.players:
		p.completed_quests.clear()
		p.trophies.clear()
	game.set_player_power(0, 35)
	game.set_player_power(1, 36)
	game.set_black_rose_power(0)
	game.check_end_game()
	check(game.pending_input.get("type") == "final_winner_choice", "Exact final tie requires First Mage decision")
	check(not game._submit_beta_input_authoritative(0, {"winner": -1}), "Cannot select a non-tied participant")
	check(game._submit_beta_input_authoritative(0, {"winner": 1}), "First Mage can select a tied winner")
	check(game.final_result.winner == 1 and not game.waiting_for_player_input, "Tie decision must finish the game")
	print("REPORTED RULES PLAYTEST: ", "PASS" if failures == 0 else str(failures) + " FAILURES")
	quit(0 if failures == 0 else 1)
