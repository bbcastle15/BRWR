extends RefCounted

const BetaHUDScript = preload("res://beta_hud.gd")


static func run(game) -> void:
	print("")
	print("========================================")
	print("BETA QUEST / FORGOTTEN AUDIT V24.1 TEST")
	print("========================================")

	var player_index := 0
	var player = game.players[player_index]

	player.active_quests.clear()
	player.completed_quests.clear()
	player.revealed_spells.clear()

	if not _test_contingent_mage(game, player_index):
		return

	if not _test_shattered_illusion(game, player_index):
		return

	if not _test_channeling_instability(game, player_index):
		return

	if not _test_summoner_wizard(game, player_index):
		return

	if not _test_holy_corruption(game, player_index):
		return

	if not _test_trap_and_protection_completion(game, player_index):
		return

	if not _test_quest_effect_handlers(game, player_index):
		return

	if not _test_quest_solve_skips_unapplicable_effect(game, player_index):
		return

	if not _test_quest_timing_inside_activation(game, player_index):
		return

	if not _test_interactive_quest_choices(game, player_index):
		return

	if not _test_line_of_sight_and_range(game, player_index):
		return

	if not _test_interactive_spell_primary_targets(game, player_index):
		return

	if not _test_interactive_spell_secondary_choices(game, player_index):
		return

	if not _test_spell_audit_v9(game, player_index):
		return

	if not _test_spell_audit_v10(game, player_index):
		return

	if not _test_beta_bridge_v11(game, player_index):
		return

	if not _test_momentum_v12(game, player_index):
		return

	if not _test_full_turn_smoke_v12(game):
		return

	if not _test_beta_legal_actions_v13(game, player_index):
		return

	if not _test_physical_attack_models_v14(game, player_index):
		return

	if not _test_evocation_activation_v15(game, player_index):
		return

	if not _test_stepwise_activation_v16(game, player_index):
		return

	if not _test_beta_hud_contract_v17(game):
		return

	if not _test_beta_hud_grouping_v18():
		return

	if not _test_room_target_choice_v18(game, player_index):
		return

	if not _test_starting_grimoire_catalog_v19(game):
		return

	if not _test_starting_grimoire_build_v19(game, player_index):
		return

	if not _test_cell_two_exits_v19(game, player_index):
		return

	if not _test_command_ui_grouping_v19():
		return

	if not _test_beta_layout_native_scale_v20(game):
		return

	if not _test_specialization_fallback_v20(game):
		return

	if not _test_mage_setup_pass_v21(game):
		return

	if not _test_quest_decks_v24(game):
		return

	if not _test_second_third_moon_task_matching_v24(game, player_index):
		return

	if not _test_duplicate_spell_preparation_v25(game, player_index):
		return

	if not _test_forgotten_beta_v24(game, player_index):
		return

	print("")
	print("========================================")
	print("BETA QUEST / FORGOTTEN AUDIT V24.1: ALL TESTS PASSED")
	print("========================================")


static func _reset_player_quests(game, player_index: int) -> void:
	var player = game.players[player_index]
	player.active_quests.clear()
	player.completed_quests.clear()


static func _new_active_quest(game, player_index: int, quest_id: String) -> QuestState:
	var card: QuestCardState = game.quest_database.get_quest(quest_id)
	if card == null:
		print("FAIL: Quest not found: ", quest_id)
		return null

	var quest := QuestState.new(card, player_index)
	if bool(card.task.get("reveal_immediately", false)):
		quest.reveal()

	game.players[player_index].active_quests.append(quest)
	return quest


static func _test_contingent_mage(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)

	var card: QuestCardState = game.quest_database.get_quest("contingent_mage")
	if card == null:
		print("FAIL: Contingent Mage not found")
		return false

	if card.cube_slots != 3:
		print("FAIL: Contingent Mage must have 3 cube slots, got ", card.cube_slots)
		return false

	# Exercise the real draw logic, including "Reveal this card."
	var old_deck: Array = game.quest_decks.get(1, []).duplicate()
	game.quest_decks[1] = [card]
	var quest: QuestState = game.quest_manager.draw_quest(game, player_index)
	game.quest_decks[1] = old_deck

	if quest == null or not quest.revealed:
		print("FAIL: Contingent Mage must be revealed when drawn")
		return false

	for i in range(3):
		game.quest_manager.process_event(game, {
			"type": "spell_resolved",
			"player_index": player_index,
			"source_kind": "spell",
			"spell_type": "contingency"
		})

	if not quest.completed or quest.progress != 3:
		print("FAIL: Contingent Mage expected 3/3 completed, got ", quest.progress)
		return false

	print("PASS: Contingent Mage -> reveal on draw + 3 Contingency Spells")
	return true


static func _test_shattered_illusion(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)
	var quest := _new_active_quest(game, player_index, "shattered_illusion")
	if quest == null:
		return false

	if quest.get_cube_slots() != 2:
		print("FAIL: Shattered Illusion must have 2 cube slots")
		return false

	game.quest_manager.process_event(game, {
		"type": "room_effect_resolved",
		"player_index": player_index,
		"source_kind": "room",
		"room_color": "red"
	})

	if quest.progress != 0:
		print("FAIL: Shattered Illusion progressed on wrong Room color")
		return false

	for i in range(2):
		game.quest_manager.process_event(game, {
			"type": "room_effect_resolved",
			"player_index": player_index,
			"source_kind": "room",
			"room_color": "blue"
		})

	if not quest.completed or quest.progress != 2:
		print("FAIL: Shattered Illusion expected 2/2 completed")
		return false

	print("PASS: Shattered Illusion -> Blue Room Effect only, 2/2")
	return true


static func _test_channeling_instability(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)
	var quest := _new_active_quest(game, player_index, "channeling_instability")
	if quest == null:
		return false

	if quest.get_cube_slots() != 4 or not quest.revealed:
		print("FAIL: Channeling Instability must start revealed with 4 slots")
		return false

	# Resolving an effect that attempts but places zero cubes must not progress.
	game.quest_manager.process_event(game, {
		"type": "effect_resolved",
		"player_index": player_index,
		"source_kind": "spell",
		"instability_placed": 0,
		"keywords": []
	})

	if quest.progress != 0:
		print("FAIL: Channeling Instability progressed with 0 cubes placed")
		return false

	for i in range(4):
		game.quest_manager.process_event(game, {
			"type": "effect_resolved",
			"player_index": player_index,
			"source_kind": "spell",
			"instability_placed": 1,
			"keywords": []
		})

	if not quest.completed or quest.progress != 4:
		print("FAIL: Channeling Instability expected 4/4 completed")
		return false

	print("PASS: Channeling Instability -> actual placed Instability, 4/4")
	return true


static func _test_summoner_wizard(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)
	var quest := _new_active_quest(game, player_index, "summoner_wizard")
	if quest == null:
		return false

	if quest.get_cube_slots() != 2 or not quest.revealed:
		print("FAIL: Summoner Wizard must start revealed with 2 slots")
		return false

	game.quest_manager.process_event(game, {
		"type": "effect_resolved",
		"player_index": player_index,
		"source_kind": "spell",
		"keywords": []
	})

	if quest.progress != 0:
		print("FAIL: Summoner Wizard progressed without Summon keyword")
		return false

	for i in range(2):
		game.quest_manager.process_event(game, {
			"type": "effect_resolved",
			"player_index": player_index,
			"source_kind": "spell",
			"keywords": ["summon"]
		})

	if not quest.completed or quest.progress != 2:
		print("FAIL: Summoner Wizard expected 2/2 completed")
		return false

	print("PASS: Summoner Wizard -> Summon keyword only, 2/2")
	return true


static func _test_holy_corruption(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)
	var player = game.players[player_index]
	player.revealed_spells.clear()

	var quest := _new_active_quest(game, player_index, "holy_corruption")
	if quest == null:
		return false

	var shared: SpellCardState = game.spell_database.get_spell("shared_torture")
	var grim: SpellCardState = game.spell_database.get_spell("grim_torment")
	var pain_mark: SpellCardState = game.spell_database.get_spell("pain_mark")

	if shared == null or grim == null or pain_mark == null:
		print("FAIL: Agony Spells required for Holy Corruption test are missing")
		return false

	# Two Profane symbols are already on Revealed Spells.
	player.add_revealed_spell(RevealedSpellState.new(shared, false))
	player.add_revealed_spell(RevealedSpellState.new(grim, false))

	# The currently resolving Spell is already revealed by the tabletop rules,
	# but the digital state adds it to revealed_spells only after resolution.
	# Its Active Side therefore supplies the third Profane symbol via the event.
	game.quest_manager.process_event(game, {
		"type": "effect_resolved",
		"player_index": player_index,
		"source_kind": "spell",
		"spell_type": "combat",
		"spell_element": "profane",
		"spell_side": pain_mark.light_side,
		"instability_placed": 0,
		"keywords": []
	})

	if not quest.completed:
		print("FAIL: Holy Corruption did not complete with 3 Profane symbols")
		return false

	print("PASS: Holy Corruption -> 3 Sacred/Profane symbols")
	return true


static func _test_trap_and_protection_completion(game, player_index: int) -> bool:
	_reset_player_quests(game, player_index)

	var guardian := _new_active_quest(game, player_index, "guardian_mage")
	var conspirator := _new_active_quest(game, player_index, "conspirator_mage")
	if guardian == null or conspirator == null:
		return false

	game.quest_manager.process_event(game, {
		"type": "spell_resolved",
		"player_index": player_index,
		"source_kind": "spell",
		"spell_type": "protection"
	})

	if not guardian.completed or conspirator.completed:
		print("FAIL: Protection event matched wrong Quest")
		return false

	game.quest_manager.process_event(game, {
		"type": "spell_resolved",
		"player_index": player_index,
		"source_kind": "spell",
		"spell_type": "trap"
	})

	if not conspirator.completed:
		print("FAIL: Conspirator Mage did not complete on Trap Spell")
		return false

	print("PASS: Guardian/Conspirator Mage -> Protection/Trap separation")
	return true


static func _test_quest_effect_handlers(game, player_index: int) -> bool:
	var player = game.players[player_index]
	var saved_hand: Array = player.hand.duplicate()
	var saved_grimoire: Array = player.grimoire.duplicate()
	var saved_memories: Array = player.memories.duplicate()
	var saved_revealed: Array = player.revealed_spells.duplicate()
	var saved_damage: Array[int] = []
	saved_damage.append_array(player.mage.damage_cubes)
	var saved_crown: int = game.crown_owner_id
	var saved_rng_state: int = game.rng.state

	var saved_libraries: Dictionary = {}
	for school_id in game.active_school_ids:
		saved_libraries[str(school_id)] = game.school_libraries[str(school_id)].duplicate()

	var shared: SpellCardState = game.spell_database.get_spell("shared_torture")
	var grim: SpellCardState = game.spell_database.get_spell("grim_torment")
	if shared == null or grim == null:
		print("FAIL: Quest Effect test Spells missing")
		return false

	# -----------------------------------------------------
	# Return a matching Revealed Spell to Hand.
	# -----------------------------------------------------
	player.hand.clear()
	player.revealed_spells.clear()
	var revealed := RevealedSpellState.new(shared, false)
	player.revealed_spells.append(revealed)

	if not game.effect_resolver.resolve_effect(
		{
			"type": "return_revealed_spell_to_hand",
			"required_elements": ["profane"]
		},
		{
			"game": game,
			"caster_id": player_index,
			"selected_revealed_spell": revealed
		}
	):
		print("FAIL: return_revealed_spell_to_hand returned false")
		return false

	if revealed in player.revealed_spells or not shared in player.hand:
		print("FAIL: Revealed Spell was not returned to Hand")
		return false

	# -----------------------------------------------------
	# Search a Spell from the Grimoire, then shuffle.
	# -----------------------------------------------------
	player.hand.clear()
	player.grimoire.clear()
	player.grimoire.append(shared)
	player.grimoire.append(grim)

	if not game.effect_resolver.resolve_effect(
		{
			"type": "search_grimoire_to_hand",
			"amount": 1
		},
		{
			"game": game,
			"caster_id": player_index,
			"selected_grimoire_spell_id": shared.id
		}
	):
		print("FAIL: search_grimoire_to_hand returned false")
		return false

	if not shared in player.hand or shared in player.grimoire:
		print("FAIL: searched Spell did not move Grimoire -> Hand")
		return false

	# -----------------------------------------------------
	# Draw one Spell from the Library.
	# -----------------------------------------------------
	player.hand.clear()
	if game.active_school_ids.is_empty():
		print("FAIL: no active Schools available for Library test")
		return false

	var school_id := str(game.active_school_ids[0])
	if not game.effect_resolver.resolve_effect(
		{"type": "draw_library", "amount": 1},
		{
			"game": game,
			"caster_id": player_index,
			"selected_school_id": school_id
		}
	):
		print("FAIL: draw_library returned false")
		return false

	if player.hand.size() != 1:
		print("FAIL: draw_library did not add exactly one Spell to Hand")
		return false

	# Restore Libraries immediately so the test does not alter setup.
	for saved_school_id in saved_libraries.keys():
		game.school_libraries[saved_school_id] = saved_libraries[saved_school_id].duplicate()

	# -----------------------------------------------------
	# Guarding Wisdom: no Damage -> draw from Grimoire.
	# -----------------------------------------------------
	player.hand.clear()
	player.grimoire.clear()
	player.grimoire.append(shared)
	player.memories.clear()
	player.mage.damage_cubes.clear()

	if not game.effect_resolver.resolve_effect(
		{"type": "draw_grimoire_or_heal", "draw": 1, "heal": 3},
		{"game": game, "caster_id": player_index}
	):
		print("FAIL: draw_grimoire_or_heal draw branch returned false")
		return false

	if player.hand.size() != 1 or player.mage.get_damage() != 0:
		print("FAIL: Guarding Wisdom draw branch is incorrect")
		return false

	# Damage branch: place one Black Rose Damage directly with its Cube resource.
	player.hand.clear()
	player.mage.damage_cubes.clear()
	if game.take_owner_cubes(-1, 1) != 1:
		print("FAIL: no Black Rose Cube available for heal test")
		return false
	player.mage.add_damage(-1, 1)

	if not game.effect_resolver.resolve_effect(
		{"type": "draw_grimoire_or_heal", "draw": 2, "heal": 3},
		{"game": game, "caster_id": player_index}
	):
		print("FAIL: draw_grimoire_or_heal heal branch returned false")
		return false

	if player.mage.get_damage() != 0:
		print("FAIL: Guarding Wisdom did not heal Damage")
		return false

	# -----------------------------------------------------
	# Convert Instability in a real Room.
	# -----------------------------------------------------
	var room = game.get_room_by_id("black_rose")
	if room == null:
		print("FAIL: Black Rose Room missing")
		return false

	# Tests run before play; the Room should be empty. Preserve it anyway.
	var saved_room_instability: Array = room.instability_cubes.duplicate()
	while not room.instability_cubes.is_empty():
		var setup_owner_id := int(room.instability_cubes[0])
		room.remove_instability_cube(setup_owner_id)
		game.return_owner_cubes(setup_owner_id, 1)

	if game.place_instability(-1, "black_rose", 1) != 1:
		print("FAIL: could not set up Instability conversion test")
		return false

	if not game.effect_resolver.resolve_effect(
		{"type": "convert_instability", "amount": 1},
		{
			"game": game,
			"caster_id": player_index,
			"target_room_id": "black_rose",
			"selected_instability_owner_ids": [-1]
		}
	):
		print("FAIL: convert_instability returned false")
		return false

	if room.get_instability_by_owner(player_index) != 1 \
	or room.get_instability_by_owner(-1) != 0:
		print("FAIL: Instability Cube owner was not converted")
		return false

	# Clear test Cubes and restore pre-test Room state.
	while not room.instability_cubes.is_empty():
		var cleanup_owner_id := int(room.instability_cubes[0])
		room.remove_instability_cube(cleanup_owner_id)
		game.return_owner_cubes(cleanup_owner_id, 1)
	for owner_value in saved_room_instability:
		game.place_instability(int(owner_value), "black_rose", 1)

	# -----------------------------------------------------
	# Crown.
	# -----------------------------------------------------
	if not game.effect_resolver.resolve_effect(
		{"type": "take_crown"},
		{"game": game, "caster_id": player_index}
	):
		print("FAIL: take_crown returned false")
		return false

	if game.crown_owner_id != player_index:
		print("FAIL: take_crown did not update Crown owner")
		return false

	# Restore state changed by this test.
	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.grimoire.clear()
	player.grimoire.append_array(saved_grimoire)
	player.memories.clear()
	player.memories.append_array(saved_memories)
	player.revealed_spells.clear()
	player.revealed_spells.append_array(saved_revealed)
	player.mage.damage_cubes.clear()
	player.mage.damage_cubes.append_array(saved_damage)
	game.crown_owner_id = saved_crown
	game.rng.state = saved_rng_state

	print("PASS: Quest Effect handlers -> Hand/Grimoire/Library/Heal/Instability/Crown")
	return true


static func _test_quest_solve_skips_unapplicable_effect(
	game,
	player_index: int
) -> bool:
	_reset_player_quests(game, player_index)
	var player = game.players[player_index]
	var old_power: int = player.power

	# A Quest Effect with no legal/selected Mage target cannot be applied.
	# The rulebook still considers the Quest Effect resolved after the attempt,
	# so the Quest must become Solved and award its Power reward.
	var card := QuestCardState.new(
		"test_unapplicable_quest",
		"Test Unapplicable Quest",
		1,
		{},
		[
			{
				"type": "damage",
				"amount": 2,
				"target": "mage"
			}
		],
		0,
		1
	)
	var quest := QuestState.new(card, player_index)
	quest.complete()
	player.completed_quests.append(quest)

	if not game.quest_manager.solve_quest(game, player_index, quest, {}):
		print("FAIL: solve_quest did not queue Quest resolution")
		return false

	if not quest.is_solved():
		print("FAIL: Quest remained Completed after unapplicable Effect")
		return false

	if player.power != old_power + 1:
		print("FAIL: solved Quest did not award Power")
		return false

	player.completed_quests.erase(quest)
	game.set_player_power(player_index, old_power)

	print("PASS: unapplicable Quest Effect is skipped -> Quest still Solved")
	return true


static func _test_quest_timing_inside_activation(
	game,
	player_index: int
) -> bool:
	_reset_player_quests(game, player_index)
	var player = game.players[player_index]

	var saved_physical_actions: int = player.available_physical_actions
	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_power: int = player.power

	player.available_physical_actions = 2
	player.mage.in_cell = false
	player.mage.room_id = "black_rose"

	# Three zero-reward Completed Quests let us verify all legal timing windows:
	# before Action 1, between Action 1/2, and after Action 2.
	for i in range(3):
		var card := QuestCardState.new(
			"timing_test_" + str(i),
			"Timing Test " + str(i),
			1,
			{},
			[],
			0,
			0
		)
		var quest := QuestState.new(card, player_index)
		quest.complete()
		player.completed_quests.append(quest)

	# Completed Quests do not replace the mandatory 1-2 Actions of an Activation.
	if game._validate_player_activation(
		player_index,
		[
			{"type": "quest", "quest_index": 0}
		]
	):
		print("FAIL: Quest-only Activation was accepted as an Action")
		return false

	# The same Completed Quest cannot be declared twice in one Activation.
	if game._validate_player_activation(
		player_index,
		[
			{"type": "quest", "quest_index": 0},
			{"type": "quest", "quest_index": 0},
			{
				"type": "explore",
				"destination_room_ids": [],
				"activate_room_before_movement": false,
				"activate_room_after_movement": false
			}
		]
	):
		print("FAIL: duplicate Quest resolution was accepted")
		return false

	var sequence: Array = [
		{"type": "quest", "quest_index": 0},
		{
			"type": "explore",
			"destination_room_ids": [],
			"activate_room_before_movement": false,
			"activate_room_after_movement": false
		},
		{"type": "quest", "quest_index": 1},
		{
			"type": "explore",
			"destination_room_ids": [],
			"activate_room_before_movement": false,
			"activate_room_after_movement": false
		},
		{"type": "quest", "quest_index": 2}
	]

	if not game.resolve_player_activation(player_index, sequence):
		print("FAIL: mixed Quest/Action Activation did not resolve")
		return false

	for quest in player.completed_quests:
		if not quest.is_solved():
			print("FAIL: Completed Quest was not Solved in Activation timing window")
			return false

	if player.available_physical_actions != 0:
		print(
			"FAIL: Quest resolution consumed an Action; expected 0 physical actions left, got ",
			player.available_physical_actions
		)
		return false

	# Cell restriction: a Completed Quest cannot be resolved while the Mage is
	# still inside their Cell. The Quest step is skipped, then the real Action
	# continues normally.
	var cell_card := QuestCardState.new(
		"cell_timing_test",
		"Cell Timing Test",
		1,
		{},
		[],
		0,
		0
	)
	var cell_quest := QuestState.new(cell_card, player_index)
	cell_quest.complete()
	player.completed_quests.append(cell_quest)
	var cell_quest_index: int = player.completed_quests.size() - 1

	player.available_physical_actions = 1
	player.mage.in_cell = true
	player.mage.room_id = ""

	if not game.resolve_player_activation(
		player_index,
		[
			{"type": "quest", "quest_index": cell_quest_index},
			{
				"type": "explore",
				"destination_room_ids": [],
				"activate_room_before_movement": false,
				"activate_room_after_movement": false
			}
		]
	):
		print("FAIL: Cell timing Activation did not resolve")
		return false

	if cell_quest.is_solved():
		print("FAIL: Completed Quest was Solved while Mage was in Cell")
		return false

	# Restore state changed by this test.
	player.completed_quests.clear()
	player.available_physical_actions = saved_physical_actions
	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	game.set_player_power(player_index, saved_power)

	print("PASS: Completed Quests resolve before/between/after Actions without consuming Actions")
	return true


static func _test_interactive_quest_choices(
	game,
	player_index: int
) -> bool:
	_reset_player_quests(game, player_index)

	var player = game.players[player_index]
	var saved_hand: Array = player.hand.duplicate()
	var saved_grimoire: Array = player.grimoire.duplicate()
	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_available_cubes: int = player.available_cubes

	player.mage.in_cell = false
	player.mage.room_id = "black_rose"

	var shared: SpellCardState = game.spell_database.get_spell("shared_torture")
	var grim: SpellCardState = game.spell_database.get_spell("grim_torment")
	if shared == null or grim == null:
		print("FAIL: interactive choice test Spells missing")
		return false

	# -----------------------------------------------------
	# 1) Grimoire choice: no automatic fallback is allowed.
	# -----------------------------------------------------
	player.hand.clear()
	player.grimoire.clear()
	player.grimoire.append(shared)
	player.grimoire.append(grim)

	var search_card := QuestCardState.new(
		"choice_search_test",
		"Choice Search Test",
		1,
		{},
		[
			{
				"type": "search_grimoire_to_hand",
				"amount": 1
			}
		],
		0,
		0
	)
	var search_quest := QuestState.new(search_card, player_index)
	search_quest.complete()
	player.completed_quests.append(search_quest)

	if not game.quest_manager.solve_quest(
		game,
		player_index,
		search_quest,
		{}
	):
		print("FAIL: interactive search Quest did not start")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("type", "")) != "effect_choice" \
	or str(game.pending_input.get("choice_kind", "")) != "grimoire_spell":
		print("FAIL: Grimoire Quest did not request an explicit choice")
		return false

	if search_quest.is_solved() or not player.hand.is_empty():
		print("FAIL: Grimoire Quest resolved before player choice")
		return false

	if game.submit_effect_choice(player_index, "not-a-valid-token"):
		print("FAIL: invalid Effect choice token was accepted")
		return false

	var search_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if str(option.get("id", "")) == grim.id:
			search_token = str(option.get("token", ""))
			break

	if search_token == "":
		print("FAIL: desired Grimoire Spell missing from choice options")
		return false

	if not game.submit_effect_choice(player_index, search_token):
		print("FAIL: valid Grimoire Effect choice was rejected")
		return false

	if not search_quest.is_solved() or not grim in player.hand:
		print("FAIL: Grimoire choice did not resume and solve Quest")
		return false

	player.completed_quests.erase(search_quest)

	# -----------------------------------------------------
	# 2) Each separate Effect gets its own target choice.
	# -----------------------------------------------------
	var room = game.get_room_by_id("black_rose")
	if room == null:
		print("FAIL: Black Rose Room missing for target-choice test")
		return false

	var initial_player_instability: int = room.get_instability_by_owner(
		player_index
	)

	var double_place_card := QuestCardState.new(
		"choice_room_test",
		"Choice Room Test",
		1,
		{},
		[
			{
				"type": "place_instability",
				"amount": 1,
				"target": "room",
				"range": 1
			},
			{
				"type": "place_instability",
				"amount": 1,
				"target": "room",
				"range": 1
			}
		],
		0,
		0
	)
	var double_place_quest := QuestState.new(
		double_place_card,
		player_index
	)
	double_place_quest.complete()
	player.completed_quests.append(double_place_quest)

	if not game.quest_manager.solve_quest(
		game,
		player_index,
		double_place_quest,
		{}
	):
		print("FAIL: double target Quest did not start")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "target_room":
		print("FAIL: first Room target choice was not requested")
		return false

	var room_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if str(option.get("room_id", "")) == "black_rose":
			room_token = str(option.get("token", ""))
			break

	if room_token == "":
		print("FAIL: caster Room missing from range-1 Room choices")
		return false

	if not game.submit_effect_choice(player_index, room_token):
		print("FAIL: first Room target choice was rejected")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "target_room":
		print("FAIL: second separate Room Effect reused the first target")
		return false

	var second_room_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if str(option.get("room_id", "")) == "black_rose":
			second_room_token = str(option.get("token", ""))
			break

	if second_room_token == "":
		print("FAIL: second Room target options missing")
		return false

	if not game.submit_effect_choice(player_index, second_room_token):
		print("FAIL: second Room target choice was rejected")
		return false

	if not double_place_quest.is_solved():
		print("FAIL: double target Quest did not finish after second choice")
		return false

	if room.get_instability_by_owner(player_index) \
	!= initial_player_instability + 2:
		print("FAIL: separate Room choices did not resolve both Effects")
		return false

	for i in range(2):
		if room.remove_instability_cube(player_index):
			game.return_owner_cubes(player_index, 1)

	player.completed_quests.erase(double_place_quest)

	# -----------------------------------------------------
	# 3) Multi-choice: choose which Instability cube converts.
	# -----------------------------------------------------
	if game.players.size() < 2:
		print("FAIL: Instability choice test needs at least 2 players")
		return false

	var opponent_index: int = 1
	if opponent_index == player_index:
		opponent_index = 0

	var initial_black_rose_instability: int = room.get_instability_by_owner(-1)
	var initial_opponent_instability: int = room.get_instability_by_owner(
		opponent_index
	)

	if game.place_instability(-1, "black_rose", 1) != 1:
		print("FAIL: could not place Black Rose Instability for choice test")
		return false

	if game.place_instability(opponent_index, "black_rose", 1) != 1:
		print("FAIL: could not place opponent Instability for choice test")
		return false

	var convert_card := QuestCardState.new(
		"choice_instability_test",
		"Choice Instability Test",
		1,
		{},
		[
			{
				"type": "convert_instability",
				"amount": 1,
				"target": "room",
				"range": 2
			}
		],
		0,
		0
	)
	var convert_quest := QuestState.new(convert_card, player_index)
	convert_quest.complete()
	player.completed_quests.append(convert_quest)

	if not game.quest_manager.solve_quest(
		game,
		player_index,
		convert_quest,
		{"target_room_id": "black_rose"}
	):
		print("FAIL: Instability conversion Quest did not start")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "instability_cubes":
		print("FAIL: Instability conversion did not request cube choice")
		return false

	var black_rose_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if int(option.get("owner_id", 999999)) == -1:
			black_rose_token = str(option.get("token", ""))
			break

	if black_rose_token == "":
		print("FAIL: Black Rose Instability missing from choice options")
		return false

	if not game.submit_effect_choice(
		player_index,
		[black_rose_token]
	):
		print("FAIL: Instability cube choice was rejected")
		return false

	if not convert_quest.is_solved():
		print("FAIL: Instability conversion Quest did not finish")
		return false

	if room.get_instability_by_owner(-1) != initial_black_rose_instability:
		print("FAIL: selected Black Rose Instability was not converted")
		return false

	if room.get_instability_by_owner(opponent_index) 	!= initial_opponent_instability + 1:
		print("FAIL: unselected opponent Instability was converted")
		return false

	# Remove the two cubes created/converted by this subtest.
	if room.remove_instability_cube(player_index):
		game.return_owner_cubes(player_index, 1)
	if room.remove_instability_cube(opponent_index):
		game.return_owner_cubes(opponent_index, 1)

	player.completed_quests.erase(convert_quest)

	# Restore player card state.
	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.grimoire.clear()
	player.grimoire.append_array(saved_grimoire)
	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	player.available_cubes = saved_available_cubes

	if game.waiting_for_player_input:
		print("FAIL: Effect choice test left pending player input")
		return false

	print("PASS: Quest Effects pause for explicit player choices and resume correctly")
	return true


static func _test_line_of_sight_and_range(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_room_coord: Vector2i = player.mage.room_coord

	# The Black Rose Room is fixed at axial coordinate (0, 0).
	player.mage.in_cell = false
	player.mage.room_id = "black_rose"
	player.mage.room_coord = Vector2i(0, 0)

	var aligned_coord := Vector2i(0, 2)
	var non_aligned_coord := Vector2i(1, 1)

	var aligned_room_id: String = game.coord_to_room_id(aligned_coord)
	var non_aligned_room_id: String = game.coord_to_room_id(non_aligned_coord)

	if aligned_room_id == "" or non_aligned_room_id == "":
		print("FAIL: LoS test could not resolve Lodge coordinates")
		player.mage.in_cell = saved_in_cell
		player.mage.room_id = saved_room_id
		player.mage.room_coord = saved_room_coord
		return false

	# Three axial directions are valid straight rows.
	if not game.has_line_of_sight_between_coords(
		Vector2i(0, 0),
		Vector2i(0, 2)
	):
		print("FAIL: same-q Rooms should have Line of Sight")
		return false

	if not game.has_line_of_sight_between_coords(
		Vector2i(0, 0),
		Vector2i(2, 0)
	):
		print("FAIL: same-r Rooms should have Line of Sight")
		return false

	if not game.has_line_of_sight_between_coords(
		Vector2i(0, 0),
		Vector2i(2, -2)
	):
		print("FAIL: same-(q+r) Rooms should have Line of Sight")
		return false

	if game.has_line_of_sight_between_coords(
		Vector2i(0, 0),
		non_aligned_coord
	):
		print("FAIL: non-aligned Rooms incorrectly have Line of Sight")
		return false

	# Numeric Range requires both distance and Line of Sight.
	if not game.is_room_within_effect_range(
		"black_rose",
		aligned_room_id,
		2
	):
		print("FAIL: aligned Room at Range 2 should be legal")
		return false

	if game.is_room_within_effect_range(
		"black_rose",
		aligned_room_id,
		1
	):
		print("FAIL: aligned Room beyond Range should be illegal")
		return false

	if game.is_room_within_effect_range(
		"black_rose",
		non_aligned_room_id,
		2
	):
		print("FAIL: numeric Range accepted Room without Line of Sight")
		return false

	# Unlimited Range ignores Line of Sight.
	if not game.is_room_within_effect_range(
		"black_rose",
		non_aligned_room_id,
		"*"
	):
		print("FAIL: unlimited Range should ignore Line of Sight")
		return false

	# Quest option generation must use the same shared targeting rule.
	var options: Array = game._quest_room_choice_options(
		player_index,
		{
			"target": "room",
			"range": 2
		}
	)

	var option_room_ids: Array[String] = []
	for option_value in options:
		var option: Dictionary = option_value
		option_room_ids.append(
			str(option.get("room_id", ""))
		)

	if not aligned_room_id in option_room_ids:
		print("FAIL: legal LoS Room missing from Quest target options")
		return false

	if non_aligned_room_id in option_room_ids:
		print("FAIL: illegal non-LoS Room present in Quest target options")
		return false

	# The same validator is available to Spells and any other targeted Effect.
	if not game.validate_target_range_from_context(
		player_index,
		"room",
		2,
		{"target_room_id": aligned_room_id}
	):
		print("FAIL: shared target validator rejected legal target")
		return false

	if game.validate_target_range_from_context(
		player_index,
		"room",
		2,
		{"target_room_id": non_aligned_room_id}
	):
		print("FAIL: shared target validator accepted target without LoS")
		return false

	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	player.mage.room_coord = saved_room_coord

	print("PASS: numeric Range requires axial Line of Sight; '*' ignores it")
	return true


static func _test_interactive_spell_primary_targets(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	if game.waiting_for_player_input:
		print("FAIL: Spell target test started with pending input")
		return false

	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_room_coord: Vector2i = player.mage.room_coord
	var saved_available_cubes: int = player.available_cubes
	var saved_revealed: Array = player.revealed_spells.duplicate()
	var saved_active_quests: Array = player.active_quests.duplicate()
	var saved_completed_quests: Array = player.completed_quests.duplicate()

	player.active_quests.clear()
	player.completed_quests.clear()
	player.mage.in_cell = false
	player.mage.room_id = "black_rose"
	player.mage.room_coord = Vector2i(0, 0)

	var target_coord := Vector2i(0, 1)
	var target_room_id: String = game.coord_to_room_id(target_coord)
	if target_room_id == "":
		print("FAIL: could not resolve adjacent Room for Spell target test")
		return false

	var room = game.get_room_by_id(target_room_id)
	if room == null:
		print("FAIL: target Room missing for Spell target test")
		return false

	var instability_before: int = room.get_instability_by_owner(player_index)

	# -----------------------------------------------------
	# 1) Room target: the Spell must pause before resolving.
	# -----------------------------------------------------
	var room_spell := SpellCardState.new(
		"interactive_room_target_test",
		"Interactive Room Target Test",
		"test",
		{
			"type": "contingency",
			"element": "magic",
			"target": "room",
			"range": 1,
			"effects": [
				{
					"type": "place_instability",
					"amount": 1
				}
			]
		},
		{
			"type": "contingency",
			"element": "magic",
			"target": "room",
			"range": 1,
			"effects": []
		}
	)

	var room_ready := ReadySpellState.new(
		room_spell,
		false
	)

	var revealed_before: int = player.revealed_spells.size()

	if not game.cast_ready_spell_state(
		player_index,
		room_ready,
		{}
	):
		print("FAIL: interactive Room Spell did not start")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "spell_target":
		print("FAIL: Room Spell did not request primary target")
		return false

	if player.revealed_spells.size() != revealed_before:
		print("FAIL: Spell resolved before target selection")
		return false

	if game.submit_effect_choice(
		player_index,
		"not-a-valid-target"
	):
		print("FAIL: invalid Spell target token was accepted")
		return false

	var room_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if str(option.get("room_id", "")) == target_room_id:
			room_token = str(option.get("token", ""))
			break

	if room_token == "":
		print("FAIL: legal Room missing from Spell target options")
		return false

	if not game.submit_effect_choice(
		player_index,
		room_token
	):
		print("FAIL: legal Spell Room target was rejected")
		return false

	if game.waiting_for_player_input:
		print("FAIL: Room Spell left pending input")
		return false

	if room.get_instability_by_owner(player_index) \
	!= instability_before + 1:
		print("FAIL: selected Room was not used by the Spell Effect")
		return false

	if player.revealed_spells.size() != revealed_before + 1:
		print("FAIL: Room Spell was not revealed after resolution")
		return false

	if room.remove_instability_cube(player_index):
		game.return_owner_cubes(player_index, 1)

	# -----------------------------------------------------
	# 2) Model target: Dummy Target is a legal explicit choice.
	#    Damage to a Dummy is ignored, but the Spell still resolves.
	# -----------------------------------------------------
	var dummy_spell := SpellCardState.new(
		"interactive_dummy_target_test",
		"Interactive Dummy Target Test",
		"test",
		{
			"type": "combat",
			"element": "fire",
			"target": "model",
			"range": 1,
			"effects": [
				{
					"type": "damage",
					"amount": 2
				}
			]
		},
		{
			"type": "combat",
			"element": "fire",
			"target": "model",
			"range": 1,
			"effects": []
		}
	)

	var dummy_ready := ReadySpellState.new(
		dummy_spell,
		false
	)

	revealed_before = player.revealed_spells.size()

	if not game.cast_ready_spell_state(
		player_index,
		dummy_ready,
		{}
	):
		print("FAIL: Dummy-target Spell did not start")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "spell_target":
		print("FAIL: Model Spell did not request primary target")
		return false

	var dummy_token: String = ""
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		if str(option.get("target_type", "")) == "dummy":
			dummy_token = str(option.get("token", ""))
			break

	if dummy_token == "":
		print("FAIL: Dummy Target missing from Model target options")
		return false

	if not game.submit_effect_choice(
		player_index,
		dummy_token
	):
		print("FAIL: Dummy Target choice was rejected")
		return false

	if game.waiting_for_player_input:
		print("FAIL: Dummy-target Spell left pending input")
		return false

	if player.revealed_spells.size() != revealed_before + 1:
		print("FAIL: Spell targeting Dummy did not resolve")
		return false

	# Restore state changed by the two synthetic Spells.
	player.revealed_spells.clear()
	player.revealed_spells.append_array(saved_revealed)
	player.active_quests.clear()
	player.active_quests.append_array(saved_active_quests)
	player.completed_quests.clear()
	player.completed_quests.append_array(saved_completed_quests)
	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	player.mage.room_coord = saved_room_coord
	player.available_cubes = saved_available_cubes

	if game.waiting_for_player_input:
		print("FAIL: Spell target test left pending player input")
		return false

	print("PASS: Combat/Contingency Spells request and use explicit primary targets")
	return true


static func _test_interactive_spell_secondary_choices(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	if game.waiting_for_player_input:
		print("FAIL: V8 secondary-choice test started with pending input")
		return false

	# -----------------------------------------------------
	# Build two temporary owned Evocations.  The choice layer only needs
	# runtime EvocationState objects; no deck copies are consumed here.
	# -----------------------------------------------------
	var first_evocation := EvocationState.new(
		"v8_construct_a",
		"V8 Construct A",
		"construct",
		3,
		1,
		1,
		player_index
	)
	first_evocation.room_id = "black_rose"

	var second_evocation := EvocationState.new(
		"v8_construct_b",
		"V8 Construct B",
		"construct",
		3,
		1,
		1,
		player_index
	)
	second_evocation.room_id = "black_rose"

	var original_evocations: Array[EvocationState] = (
		player.evocations.duplicate()
	)

	player.evocations.clear()
	player.evocations.append(first_evocation)
	player.evocations.append(second_evocation)

	# -----------------------------------------------------
	# 1) "One of your Evocations activates" must ask which one.
	# -----------------------------------------------------
	var activation_context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"resolver_kind": "spell"
	}

	var activation_effect: Dictionary = {
		"type": "activate_owned_evocation",
		"evocation_archetype": "construct",
		"strength_bonus": 1
	}

	if game._prepare_spell_secondary_effect_choice(
		activation_effect,
		activation_context
	):
		print("FAIL: multiple owned Evocations were auto-selected")
		player.evocations.clear()
		player.evocations.append_array(original_evocations)
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("choice_kind", "")) != "owned_evocation":
		print("FAIL: owned-Evocation choice was not requested")
		player.evocations.clear()
		player.evocations.append_array(original_evocations)
		return false

	var activation_options: Array = game.pending_input.get(
		"options",
		[]
	)

	if activation_options.size() != 2:
		print("FAIL: expected two owned-Evocation options")
		return false

	var second_token: String = str(
		activation_options[1].get("token", "")
	)

	if not game.submit_effect_choice(
		player_index,
		second_token
	):
		print("FAIL: owned-Evocation selection rejected")
		return false

	if activation_context.get(
		"selected_evocation_to_activate",
		null
	) != second_evocation:
		print("FAIL: wrong owned Evocation stored in Effect context")
		return false

	game._clear_spell_secondary_effect_choices(
		activation_effect,
		activation_context
	)

	if activation_context.has("selected_evocation_to_activate"):
		print("FAIL: secondary Evocation choice leaked after Effect")
		return false

	# -----------------------------------------------------
	# 2) Deflagrate-style movement is a two-stage decision:
	#    damaged Model first, destination second.
	# -----------------------------------------------------
	var movement_context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"resolver_kind": "spell",
		"models_damaged_by_effect": [
			{
				"type": "evocation",
				"evocation": first_evocation
			},
			{
				"type": "evocation",
				"evocation": second_evocation
			}
		]
	}

	var movement_effect: Dictionary = {
		"type": "move_one_model_damaged_by_effect",
		"distance": 1
	}

	if game._prepare_spell_secondary_effect_choice(
		movement_effect,
		movement_context
	):
		print("FAIL: damaged Model was auto-selected with two options")
		return false

	if str(game.pending_input.get("choice_kind", "")) != "damaged_model":
		print("FAIL: damaged Model choice not requested")
		return false

	var damaged_options: Array = game.pending_input.get(
		"options",
		[]
	)

	var damaged_token: String = str(
		damaged_options[0].get("token", "")
	)

	if not game.submit_effect_choice(
		player_index,
		damaged_token
	):
		print("FAIL: damaged Model choice rejected")
		return false

	if not movement_context.has("damaged_model_to_move_index"):
		print("FAIL: damaged Model index not stored")
		return false

	if game._prepare_spell_secondary_effect_choice(
		movement_effect,
		movement_context
	):
		print("FAIL: movement destination should require a choice")
		return false

	if str(game.pending_input.get("choice_kind", "")) \
	!= "movement_destination":
		print("FAIL: movement destination choice not requested")
		return false

	var destination_options: Array = game.pending_input.get(
		"options",
		[]
	)

	if destination_options.is_empty():
		print("FAIL: no legal movement destinations were generated")
		return false

	var destination_token: String = str(
		destination_options[0].get("token", "")
	)

	if not game.submit_effect_choice(
		player_index,
		destination_token
	):
		print("FAIL: movement destination choice rejected")
		return false

	if str(
		movement_context.get(
			"movement_destination_room_id",
			""
		)
	) == "":
		print("FAIL: movement destination not stored")
		return false

	game._clear_spell_secondary_effect_choices(
		movement_effect,
		movement_context
	)

	# -----------------------------------------------------
	# 3) Silver/Fountain-style OR branches are explicit decisions.
	# -----------------------------------------------------
	var silver_context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"resolver_kind": "spell"
	}

	var silver_effect: Dictionary = {
		"type": "silver_defeat_choice"
	}

	if game._prepare_spell_secondary_effect_choice(
		silver_effect,
		silver_context
	):
		print("FAIL: Silver branch was auto-selected with two legal branches")
		return false

	if str(game.pending_input.get("choice_kind", "")) != "silver_choice":
		print("FAIL: Silver branch choice not requested")
		return false

	var activate_construct_token: String = ""

	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value

		if str(option.get("token", "")) == "silver:activate_construct":
			activate_construct_token = str(option.get("token", ""))
			break

	if activate_construct_token == "":
		print("FAIL: Silver activate-Construct branch missing")
		return false

	if not game.submit_effect_choice(
		player_index,
		activate_construct_token
	):
		print("FAIL: Silver branch selection rejected")
		return false

	# With two Constructs, choosing the branch must immediately lead to a
	# second decision for which Construct activates.
	if game._prepare_spell_secondary_effect_choice(
		silver_effect,
		silver_context
	):
		print("FAIL: Silver Construct was auto-selected with two options")
		return false

	if str(game.pending_input.get("choice_kind", "")) \
	!= "construct_to_activate":
		print("FAIL: Silver Construct choice not requested")
		return false

	var construct_options: Array = game.pending_input.get(
		"options",
		[]
	)

	if construct_options.size() != 2:
		print("FAIL: Silver did not offer both Constructs")
		return false

	var construct_token: String = str(
		construct_options[0].get("token", "")
	)

	if not game.submit_effect_choice(
		player_index,
		construct_token
	):
		print("FAIL: Silver Construct selection rejected")
		return false

	if silver_context.get(
		"selected_evocation_to_activate",
		null
	) == null:
		print("FAIL: Silver Construct selection not stored")
		return false

	game._clear_spell_secondary_effect_choices(
		silver_effect,
		silver_context
	)

	# Restore original Evocations.
	player.evocations.clear()
	player.evocations.append_array(original_evocations)

	if game.waiting_for_player_input:
		print("FAIL: V8 secondary-choice test left pending input")
		return false

	print("PASS: Spell secondary decisions pause, store choices and resume in stages")
	return true


static func _test_spell_audit_v9(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V9 audit test needs at least two players")
		return false

	if game._enhancement_required_elements(
		{"requires": ["water", "earth"]}
	) != ["water", "earth"]:
		print("FAIL: Enhancement 'requires' schema not normalized")
		return false

	if game._enhancement_required_elements(
		{"elements": ["air", "earth"]}
	) != ["air", "earth"]:
		print("FAIL: Enhancement 'elements' schema not normalized")
		return false

	if game._enhancement_required_elements(
		{"element": "water"}
	) != ["water"]:
		print("FAIL: Enhancement 'element' schema not normalized")
		return false

	var grim: SpellCardState = game.spell_database.get_spell(
		"grim_torment"
	)

	if grim == null:
		print("FAIL: Grim Torment missing")
		return false

	if str(grim.light_side.get("type", "")) != "combat" \
	or str(grim.light_side.get("element", "")) != "profane" \
	or str(grim.light_side.get("target", "")) != "model" \
	or int(grim.light_side.get("range", -1)) != 2:
		print("FAIL: Grim Torment Light metadata does not match card")
		return false

	if str(grim.dark_side.get("type", "")) != "combat" \
	or str(grim.dark_side.get("element", "")) != "profane" \
	or str(grim.dark_side.get("target", "")) != "room" \
	or int(grim.dark_side.get("range", -1)) != 2:
		print("FAIL: Grim Torment Dark metadata does not match card")
		return false

	var grim_dark_effects: Array = grim.dark_side.get("effects", [])
	if grim_dark_effects.size() != 2 \
	or str(grim_dark_effects[0].get("type", "")) != "pain" \
	or str(grim_dark_effects[1].get("type", "")) != "damage_per_self_damage":
		print("FAIL: Grim Torment Dark effects are incorrect")
		return false

	var cross: SpellCardState = game.spell_database.get_spell(
		"cross_and_delight"
	)
	var aludel: SpellCardState = game.spell_database.get_spell(
		"purifying_aludel"
	)

	if cross == null or str(
		cross.dark_side.get("target_owner", "")
	) != "self":
		print("FAIL: Cross and Delight does not restrict target to your Demon")
		return false

	if aludel == null or str(
		aludel.light_side.get("target_owner", "")
	) != "self":
		print("FAIL: Purifying Aludel does not restrict Light target to yours")
		return false

	var caster = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_caster_room: String = caster.mage.room_id
	var saved_opponent_room: String = opponent.mage.room_id
	var saved_caster_cell: bool = caster.mage.in_cell
	var saved_opponent_cell: bool = opponent.mage.in_cell
	var saved_caster_damage: Array[int] = caster.mage.damage_cubes.duplicate()
	var saved_opponent_damage: Array[int] = opponent.mage.damage_cubes.duplicate()
	var saved_caster_evocations: Array[EvocationState] = caster.evocations.duplicate()
	var saved_cubes: int = caster.available_cubes

	caster.mage.in_cell = false
	opponent.mage.in_cell = false
	caster.mage.room_id = "black_rose"
	opponent.mage.room_id = "black_rose"

	caster.mage.damage_cubes.clear()
	opponent.mage.damage_cubes.clear()

	var demon := EvocationState.new(
		"v9_demon",
		"V9 Demon",
		"demon",
		3,
		1,
		2,
		player_index
	)
	demon.room_id = "black_rose"
	demon.controller_id = player_index
	demon.damage_cubes.clear()
	demon.damage_cubes.append(opponent_index)

	caster.evocations.clear()
	caster.evocations.append(demon)

	var room_damage_context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"spell_target_type": "room",
		"target_room_id": "black_rose"
	}

	if not game.effect_resolver.resolve_effect(
		{
			"type": "damage",
			"amount": 1,
			"target": "room"
		},
		room_damage_context
	):
		print("FAIL: Room Damage Effect failed during immunity test")
		return false

	if caster.mage.get_damage() != 0:
		print("FAIL: caster suffered Damage from own Effect")
		return false

	if demon.get_damage() != 1:
		print("FAIL: controlled Evocation suffered Damage from caster Effect")
		return false

	if opponent.mage.get_damage() != 1:
		print("FAIL: opponent did not suffer Room Damage")
		return false

	opponent.mage.damage_cubes.clear()

	var cross_context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"spell_target_type": "evocation",
		"target_evocation": demon,
		"target_model_type": "evocation"
	}

	if not game.effect_resolver.resolve_effect(
		{
			"type": "damage_from_evocation",
			"base_amount": 2,
			"bonus_per_evocation_damage": 1
		},
		cross_context
	):
		print("FAIL: Cross and Delight Room-damage handler failed")
		return false

	if opponent.mage.get_damage() != 3:
		print(
			"FAIL: Cross and Delight expected 3 Room Damage, got ",
			opponent.mage.get_damage()
		)
		return false

	if caster.mage.get_damage() != 0 or demon.get_damage() != 1:
		print("FAIL: Cross and Delight ignored Effect immunity")
		return false

	caster.mage.damage_cubes.clear()
	caster.mage.damage_cubes.append(opponent_index)
	demon.damage_cubes.clear()
	demon.damage_cubes.append(opponent_index)

	if not game.effect_resolver.resolve_effect(
		{"type": "convert_damage", "amount": 1},
		{
			"game": game,
			"caster_id": player_index,
			"spell_target_type": "mage",
			"target_player_index": player_index
		}
	):
		print("FAIL: caster conversion immunity Effect failed")
		return false

	if caster.mage.damage_cubes != [opponent_index]:
		print("FAIL: caster converted Damage on self with own Effect")
		return false

	if not game.effect_resolver.resolve_effect(
		{"type": "convert_damage", "amount": 1},
		{
			"game": game,
			"caster_id": player_index,
			"spell_target_type": "evocation",
			"target_evocation": demon
		}
	):
		print("FAIL: controlled-Evocation conversion immunity Effect failed")
		return false

	if demon.damage_cubes != [opponent_index]:
		print("FAIL: caster converted Damage on controlled Evocation")
		return false

	caster.mage.room_id = saved_caster_room
	opponent.mage.room_id = saved_opponent_room
	caster.mage.in_cell = saved_caster_cell
	opponent.mage.in_cell = saved_opponent_cell
	caster.mage.damage_cubes.clear()
	caster.mage.damage_cubes.append_array(saved_caster_damage)
	opponent.mage.damage_cubes.clear()
	opponent.mage.damage_cubes.append_array(saved_opponent_damage)
	caster.evocations.clear()
	caster.evocations.append_array(saved_caster_evocations)
	caster.available_cubes = saved_cubes

	print("PASS: V9 audit fixes Enhancement schemas, immunity, Grim Torment and Cross/Aludel targeting")
	return true


static func _test_spell_audit_v10(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V10 audit test needs at least two players")
		return false

	# -----------------------------------------------------
	# 1) Printed/data audit: Purifying Aludel + Liquid Fire.
	# -----------------------------------------------------
	var aludel: SpellCardState = game.spell_database.get_spell(
		"purifying_aludel"
	)
	var liquid: SpellCardState = game.spell_database.get_spell(
		"liquid_fire"
	)

	if aludel == null or liquid == null:
		print("FAIL: V10 audited Alchemy card missing")
		return false

	var aludel_enhancement: Dictionary = aludel.light_side.get(
		"enhancement",
		{}
	)

	if game._enhancement_required_elements(
		aludel_enhancement
	) != ["water", "earth"]:
		print("FAIL: Purifying Aludel Enhancement must be Water + Earth")
		return false

	if str(liquid.light_side.get("target_owner", "")) != "self":
		print("FAIL: Liquid Fire Light must target one of caster's Evocations")
		return false

	# -----------------------------------------------------
	# 2) Enhancement target override: Deflagrate Enhancement changes
	#    primary target from Model to Room.
	# -----------------------------------------------------
	var synthetic_side: Dictionary = {
		"type": "combat",
		"target": "model",
		"range": 2,
		"enhancement": {
			"effects": [
				{
					"type": "modify_spell_target",
					"target": "room",
					"range": 2
				}
			]
		}
	}

	# Empty required-elements list means the synthetic Enhancement is active.
	var effective_side: Dictionary = game._spell_effective_target_side(
		player_index,
		synthetic_side
	)

	if str(effective_side.get("target", "")) != "room":
		print("FAIL: active target-changing Enhancement did not change target")
		return false

	# -----------------------------------------------------
	# 3) Ongoing Combat/Contingency trigger registration.
	# -----------------------------------------------------
	var persistent_spell := SpellCardState.new(
		"v10_ongoing_test",
		"V10 Ongoing Test",
		"agony",
		{
			"type": "combat",
			"element": "profane",
			"target": "mage",
			"range": "*",
			"trigger": {
				"type": "marked_mage_gains_or_loses_power"
			},
			"effects": [
				{
					"type": "damage_marked_mage",
					"amount": 1
				}
			]
		},
		{
			"type": "combat",
			"element": "profane",
			"target": "mage",
			"range": "*",
			"effects": []
		}
	)

	var player = game.players[player_index]
	var original_active: Array[ActiveSpellState] = player.active_spells.duplicate()

	game._register_ongoing_revealed_spell(
		player_index,
		persistent_spell,
		false,
		{
			"target_player_index": 1 if player_index == 0 else 0,
			"target_model_type": "mage"
		}
	)

	if player.active_spells.size() != original_active.size() + 1:
		print("FAIL: ongoing revealed Spell was not registered")
		return false

	var ongoing: ActiveSpellState = player.active_spells[
		player.active_spells.size() - 1
	]

	if not ongoing.active \
	or ongoing.get_trigger().is_empty():
		print("FAIL: registered ongoing Spell is not triggerable")
		return false

	player.active_spells.clear()
	player.active_spells.append_array(original_active)

	# -----------------------------------------------------
	# 4) Generic scaled Damage must work on a Room target.
	# -----------------------------------------------------
	var caster = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_caster_room: String = caster.mage.room_id
	var saved_opponent_room: String = opponent.mage.room_id
	var saved_caster_cell: bool = caster.mage.in_cell
	var saved_opponent_cell: bool = opponent.mage.in_cell
	var saved_caster_damage: Array[int] = caster.mage.damage_cubes.duplicate()
	var saved_opponent_damage: Array[int] = opponent.mage.damage_cubes.duplicate()
	var saved_cubes: int = caster.available_cubes

	caster.mage.in_cell = false
	opponent.mage.in_cell = false
	caster.mage.room_id = "black_rose"
	opponent.mage.room_id = "black_rose"

	caster.mage.damage_cubes.clear()
	caster.mage.damage_cubes.append(-1)
	caster.mage.damage_cubes.append(-1)
	opponent.mage.damage_cubes.clear()

	if not game.effect_resolver.resolve_effect(
		{
			"type": "damage_per_black_rose_damage",
			"step": 1,
			"damage_per_step": 1,
			"max": 5
		},
		{
			"game": game,
			"caster_id": player_index,
			"spell_target_type": "room",
			"target_room_id": "black_rose"
		}
	):
		print("FAIL: scaled Room Damage handler failed")
		return false

	if opponent.mage.get_damage() != 2:
		print(
			"FAIL: scaled Room Damage expected 2, got ",
			opponent.mage.get_damage()
		)
		return false

	if caster.mage.get_damage() != 2:
		print("FAIL: scaled Room Damage bypassed caster Effect immunity")
		return false

	# -----------------------------------------------------
	# 5) Heart of Ice uses target_room_id.
	# -----------------------------------------------------
	var rose_room = game.get_room_by_id("black_rose")
	if rose_room == null:
		print("FAIL: Black Rose Room missing")
		return false

	var instability_before: int = rose_room.get_instability_by_owner(
		player_index
	)

	if not game.effect_resolver.resolve_effect(
		{
			"type": "place_instability_per_self_black_rose_damage",
			"instability_per_damage": 1,
			"max": 4
		},
		{
			"game": game,
			"caster_id": player_index,
			"spell_target_type": "room",
			"target_room_id": "black_rose"
		}
	):
		print("FAIL: Heart of Ice target Room handler failed")
		return false

	var instability_after: int = rose_room.get_instability_by_owner(
		player_index
	)

	if instability_after <= instability_before:
		print("FAIL: Heart of Ice did not use target_room_id")
		return false

	while rose_room.get_instability_by_owner(player_index) > instability_before:
		if not rose_room.remove_instability_cube(player_index):
			break
		game.return_owner_cubes(player_index, 1)

	# Restore Mage state.
	caster.mage.room_id = saved_caster_room
	opponent.mage.room_id = saved_opponent_room
	caster.mage.in_cell = saved_caster_cell
	opponent.mage.in_cell = saved_opponent_cell

	caster.mage.damage_cubes.clear()
	caster.mage.damage_cubes.append_array(saved_caster_damage)
	opponent.mage.damage_cubes.clear()
	opponent.mage.damage_cubes.append_array(saved_opponent_damage)
	caster.available_cubes = saved_cubes

	print("PASS: V10 audit fixes ongoing triggers, target-changing Enhancements and Room-scoped effects")
	return true


static func _test_beta_bridge_v11(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V11 beta bridge test needs at least two players")
		return false

	var owner_id: int = player_index
	var other_id: int = 1 if owner_id == 0 else 0
	var owner = game.players[owner_id]

	# -----------------------------------------------------
	# 1) Stable UI input contract covers every interactive request type.
	# -----------------------------------------------------
	var supported: Array[String] = game.get_beta_supported_input_types()
	var expected: Array[String] = [
		"effect_choice",
		"action_activation",
		"action_activation_step",
		"preparation",
		"study_choose_schools",
		"study_keep_cards",
		"study_optional_discard",
		"study_hand_limit",
		"trigger_decision",
		"evocation_phase_activations",
		"cleanup_active_spells",
		"black_rose_optional_quest_discard",
		"black_rose_active_quest_limit",
		"black_rose_completed_quest_limit"
	]

	for input_type in expected:
		if not supported.has(input_type):
			print("FAIL: beta input router missing ", input_type)
			return false

	# -----------------------------------------------------
	# 2) Public snapshot does not leak another player's Hand.
	# -----------------------------------------------------
	var owner_state: Dictionary = game.get_beta_game_state(owner_id)
	var other_view: Dictionary = game.get_beta_game_state(other_id)

	if int(owner_state.get("player_count", 0)) != game.players.size():
		print("FAIL: beta state has wrong player count")
		return false

	var owner_players: Array = owner_state.get("players", [])
	var other_players: Array = other_view.get("players", [])

	if owner_players.size() != game.players.size() \
	or other_players.size() != game.players.size():
		print("FAIL: beta state player array malformed")
		return false

	var owner_private: Dictionary = owner_players[owner_id]
	var owner_from_other: Dictionary = other_players[owner_id]

	if not owner_private.has("hand"):
		print("FAIL: player cannot see own Hand in beta state")
		return false

	if owner_from_other.has("hand"):
		print("FAIL: beta state leaked opponent Hand")
		return false

	if int(owner_private.get("hand_count", -1)) != owner.hand.size():
		print("FAIL: beta Hand count does not match runtime state")
		return false

	# -----------------------------------------------------
	# 3) Pending requests expose private data only to the answering player.
	# -----------------------------------------------------
	var saved_waiting: bool = game.waiting_for_player_input
	var saved_pending: Dictionary = game.pending_input.duplicate(true)

	game.waiting_for_player_input = true
	game.pending_input = {
		"type": "preparation",
		"phase": game.PHASE_PREPARATION,
		"player_index": owner_id,
		"hand": [
			{
				"id": "secret_test_card",
				"name": "Secret Test Card"
			}
		]
	}

	var private_request: Dictionary = game.get_beta_pending_input(owner_id)
	var public_request: Dictionary = game.get_beta_pending_input(other_id)

	if not private_request.has("hand"):
		print("FAIL: answering player cannot see private request data")
		return false

	if public_request.has("hand") \
	or not bool(public_request.get("private", false)):
		print("FAIL: pending request leaked private information")
		return false

	game.waiting_for_player_input = saved_waiting
	game.pending_input = saved_pending

	# -----------------------------------------------------
	# 4) Clean-up safety:
	#    ongoing revealed Combat/Contingency can NEVER return to Hand,
	#    whereas an Active Trap/Protection may.
	# -----------------------------------------------------
	var saved_hand: Array[SpellCardState] = owner.hand.duplicate()
	var saved_memories: Array[SpellCardState] = owner.memories.duplicate()
	var saved_active: Array[ActiveSpellState] = owner.active_spells.duplicate()
	var saved_revealed: Array[RevealedSpellState] = owner.revealed_spells.duplicate()
	var saved_ready: Array[ReadySpellState] = owner.ready_spells.duplicate()
	var saved_quick: ReadySpellState = owner.quick_spell
	var saved_actions: int = owner.available_physical_actions

	var ongoing_spell := SpellCardState.new(
		"v11_ongoing_cleanup",
		"V11 Ongoing Cleanup",
		"agony",
		{
			"type": "combat",
			"element": "profane",
			"target": "mage",
			"range": "*",
			"trigger": {
				"type": "marked_mage_gains_or_loses_power"
			},
			"effects": []
		},
		{
			"type": "combat",
			"element": "profane",
			"target": "mage",
			"range": "*",
			"effects": []
		}
	)

	var trap_spell := SpellCardState.new(
		"v11_cleanup_trap",
		"V11 Cleanup Trap",
		"agony",
		{
			"type": "trap",
			"element": "air",
			"target": "mage",
			"range": "*",
			"trigger": {
				"type": "another_model_inflicts_damage"
			},
			"effects": []
		},
		{
			"type": "trap",
			"element": "air",
			"target": "mage",
			"range": "*",
			"effects": []
		}
	)

	owner.hand.clear()
	owner.memories.clear()
	owner.active_spells.clear()
	owner.revealed_spells.clear()
	owner.ready_spells.clear()
	owner.quick_spell = null

	var ongoing_active := ActiveSpellState.new(
		ongoing_spell,
		owner_id,
		false,
		other_id
	)
	var trap_active := ActiveSpellState.new(
		trap_spell,
		owner_id,
		false,
		other_id
	)

	owner.active_spells.append(ongoing_active)
	owner.active_spells.append(trap_active)
	owner.revealed_spells.append(
		RevealedSpellState.new(
			ongoing_spell,
			false
		)
	)

	# Intentionally request BOTH indices back. The helper itself must still
	# refuse to return a non-Trap/Protection ongoing Spell to Hand.
	var return_active_indices: Array[int] = [0, 1]

	game._cleanup_player_mage_sheet(
		owner_id,
		return_active_indices
	)

	if owner.hand.count(ongoing_spell) != 0:
		print("FAIL: ongoing Combat Spell returned to Hand during Clean-up")
		return false

	if owner.memories.count(ongoing_spell) != 1:
		print("FAIL: ongoing Combat Spell did not enter Memories exactly once")
		return false

	if owner.hand.count(trap_spell) != 1:
		print("FAIL: Active Trap was not returned to Hand")
		return false

	# Restore player state.
	owner.hand.clear()
	owner.hand.append_array(saved_hand)
	owner.memories.clear()
	owner.memories.append_array(saved_memories)
	owner.active_spells.clear()
	owner.active_spells.append_array(saved_active)
	owner.revealed_spells.clear()
	owner.revealed_spells.append_array(saved_revealed)
	owner.ready_spells.clear()
	owner.ready_spells.append_array(saved_ready)
	owner.quick_spell = saved_quick
	owner.available_physical_actions = saved_actions

	print("PASS: beta state/input bridge preserves hidden information and Clean-up rules")
	return true


static func _test_momentum_v12(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_room_coord: Vector2i = player.mage.room_coord
	var saved_hand: Array[SpellCardState] = player.hand.duplicate()
	var saved_memories: Array[SpellCardState] = player.memories.duplicate()
	var saved_ready: Array[ReadySpellState] = player.ready_spells.duplicate()
	var saved_quick: ReadySpellState = player.quick_spell

	player.hand.clear()
	player.memories.clear()
	player.ready_spells.clear()
	player.quick_spell = null

	var test_spell := SpellCardState.new(
		"v12_momentum_test",
		"V12 Momentum Test",
		"agony",
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		},
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		}
	)

	player.ready_spells.append(
		ReadySpellState.new(
			test_spell,
			false
		)
	)

	var entrance_room_id: String = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)

	if entrance_room_id == "":
		print("FAIL: Momentum test has no entrance Room")
		return false

	player.mage.in_cell = true
	player.mage.room_id = entrance_room_id
	player.mage.room_coord = game.room_id_to_coord(
		entrance_room_id
	)

	if not game.player_has_available_action(player_index):
		print("FAIL: Ready Spell does not enable Momentum from Cell")
		return false

	if not game.perform_momentum_action(
		player_index,
		0,
		false,
		entrance_room_id,
		{}
	):
		print("FAIL: Momentum Action did not start")
		return false

	if player.mage.in_cell:
		print("FAIL: Momentum did not move Mage out of Cell")
		return false

	if not player.ready_spells.is_empty():
		print("FAIL: Momentum did not discard Ready Spell")
		return false

	if player.memories.count(test_spell) != 1:
		print("FAIL: Momentum did not put Spell in Memories exactly once")
		return false

	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	player.mage.room_coord = saved_room_coord

	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.memories.clear()
	player.memories.append_array(saved_memories)
	player.ready_spells.clear()
	player.ready_spells.append_array(saved_ready)
	player.quick_spell = saved_quick

	print("PASS: Momentum discards a Ready Spell and can leave the Cell")
	return true


static func _beta_smoke_choose_two_distinct_cards(
	cards: Array
) -> Array:
	for first in range(cards.size()):
		for second in range(first + 1, cards.size()):
			var first_id: String = str(
				cards[first].get("id", "")
			)
			var second_id: String = str(
				cards[second].get("id", "")
			)

			if first_id != "" \
			and second_id != "" \
			and first_id != second_id:
				return [first, second]

	if cards.size() >= 2:
		return [0, 1]

	return []


static func _test_duplicate_spell_preparation_v25(
	game,
	player_index: int
) -> bool:
	print("")
	print("--- DUPLICATE SPELL PREPARATION V25 ---")

	if not game.spell_database.spells.has("shared_torture"):
		print("FAIL: Shared Torture definition not found")
		return false

	var definition: SpellCardState = (
		game.spell_database.spells["shared_torture"]
	)

	var copy_a: SpellCardState = game.clone_spell_card(definition)
	var copy_b: SpellCardState = game.clone_spell_card(definition)

	if copy_a == null or copy_b == null:
		print("FAIL: could not clone duplicate Spell copies")
		return false

	if copy_a == copy_b:
		print("FAIL: duplicate Spell copies share the same runtime instance")
		return false

	if copy_a.id != copy_b.id:
		print("FAIL: cloned copies must keep the same Spell id")
		return false

	var player = game.players[player_index]
	var saved_hand: Array[SpellCardState] = player.hand.duplicate()
	var saved_ready: Array[ReadySpellState] = player.ready_spells.duplicate()
	var saved_quick: ReadySpellState = player.quick_spell

	player.hand.clear()
	player.ready_spells.clear()
	player.quick_spell = null
	player.hand.append(copy_a)
	player.hand.append(copy_b)

	var prepared: bool = game.prepare_player_spells(
		player_index,
		[0, 1],
		[false, true],
		-1,
		false
	)

	var passed: bool = prepared
	passed = passed and player.hand.is_empty()
	passed = passed and player.ready_spells.size() == 2

	if passed:
		passed = (
			player.ready_spells[0].spell.id == "shared_torture"
			and player.ready_spells[1].spell.id == "shared_torture"
			and player.ready_spells[0].spell != player.ready_spells[1].spell
			and not player.ready_spells[0].use_dark_side
			and player.ready_spells[1].use_dark_side
		)

	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.ready_spells.clear()
	player.ready_spells.append_array(saved_ready)
	player.quick_spell = saved_quick

	if not passed:
		print("FAIL: two physical copies of the same Spell were not prepared independently")
		return false

	print("PASS: duplicate Spell copies are distinct and can fill separate Ready slots")
	return true


static func _beta_smoke_payload(
	game,
	request: Dictionary
) -> Dictionary:
	var input_type: String = str(
		request.get("type", "")
	)

	match input_type:
		"starting_mage_choice":
			var mages: Array = request.get(
				"available_mages",
				[]
			)

			if mages.is_empty():
				return {}

			return {
				"mage_id": str(
					mages[0].get(
						"id",
						""
					)
				)
			}

		"starting_school_choice":
			var schools: Array = request.get(
				"available_schools",
				[]
			)

			if schools.is_empty():
				return {}

			return {
				"school_id": str(
					schools[0].get(
						"id",
						""
					)
				)
			}

		"starting_grimoire_choice":
			var options: Array = request.get(
				"options",
				[]
			)

			if options.is_empty():
				return {}

			return {
				"grimoire_id": str(
					options[0].get(
						"id",
						""
					)
				)
			}

		"black_rose_optional_quest_discard":
			return {
				"quest_index": -1
			}

		"black_rose_active_quest_limit", \
		"black_rose_completed_quest_limit":
			var discard_count: int = int(
				request.get("discard_count", 0)
			)
			var indices: Array = []
			for i in range(discard_count):
				indices.append(i)
			return {
				"quest_indices": indices
			}

		"study_choose_schools":
			var schools: Array = request.get(
				"active_school_ids",
				[]
			)

			if schools.is_empty():
				return {}

			var choices: Array = []
			for i in range(4):
				choices.append(
					schools[i % schools.size()]
				)

			return {
				"school_ids": choices
			}

		"study_keep_cards":
			var cards: Array = request.get("cards", [])
			var keep: Array = _beta_smoke_choose_two_distinct_cards(
				cards
			)

			if keep.size() != 2:
				return {}

			return {
				"keep_indices": keep
			}

		"study_optional_discard":
			return {
				"hand_index": -1
			}

		"study_hand_limit":
			var discard_count: int = int(
				request.get("discard_count", 0)
			)
			var hand_indices: Array = []
			for i in range(discard_count):
				hand_indices.append(i)
			return {
				"hand_indices": hand_indices
			}

		"preparation":
			var hand: Array = request.get("hand", [])
			var pair: Array = _beta_smoke_choose_two_distinct_cards(
				hand
			)

			if pair.size() != 2:
				return {}

			return {
				"ready_hand_indices": [
					int(hand[pair[0]].get("hand_index", -1)),
					int(hand[pair[1]].get("hand_index", -1))
				],
				"ready_dark_sides": [
					false,
					false
				],
				"quick_hand_index": -1,
				"quick_dark_side": false
			}

		"action_activation_step":
			var options: Array = request.get(
				"options",
				[]
			)

			# Prefer Momentum while prepared cards remain. This keeps the
			# game-loop smoke independent of individual Spell Effects.
			for option_value in options:
				var option: Dictionary = option_value
				var action: Dictionary = option.get(
					"action",
					{}
				)

				if str(option.get("kind", "")) == "action" \
				and str(action.get("type", "")) == "momentum":
					return {
						"token": str(option.get("token", ""))
					}

			# Then consume Physical Action Tokens with any legal Explore.
			for option_value in options:
				var option: Dictionary = option_value
				var action: Dictionary = option.get(
					"action",
					{}
				)

				if str(option.get("kind", "")) == "action" \
				and str(action.get("type", "")) == "explore":
					return {
						"token": str(option.get("token", ""))
					}

			# Once at least one Action has resolved, ending the Activation is
			# always a legal beta choice.
			for option_value in options:
				var option: Dictionary = option_value

				if str(option.get("kind", "")) == "finish":
					return {
						"token": str(option.get("token", ""))
					}

			return {}

		"effect_choice":
			var options: Array = request.get("options", [])
			if options.is_empty():
				return {}

			var max_select: int = int(
				request.get("max_select", 1)
			)

			if max_select <= 1:
				return {
					"selection": options[0].get(
						"token",
						null
					)
				}

			var selection: Array = []
			var amount: int = min(
				max_select,
				options.size()
			)

			for i in range(amount):
				selection.append(
					options[i].get(
						"token",
						null
					)
				)

			return {
				"selection": selection
			}

		"trigger_decision":
			return {
				"queue_index": -1
			}

		"evocation_phase_activations":
			var choices: Array = []

			for option_value in request.get(
				"evocations",
				[]
			):
				var option: Dictionary = option_value
				var plans: Array = option.get(
					"activation_plans",
					[]
				)

				if plans.is_empty():
					return {}

				var plan: Dictionary = plans[0]

				choices.append({
					"evocation_index": int(
						option.get(
							"evocation_index",
							-1
						)
					),
					"context": plan.get(
						"context",
						{}
					).duplicate(true)
				})

			return {
				"choices": choices
			}

		"cleanup_active_spells":
			return {
				"return_to_hand_indices": []
			}

		_:
			return {}


static func _test_full_turn_smoke_v12(
	game
) -> bool:
	if game.players.is_empty():
		print("FAIL: full-turn smoke has no players")
		return false

	# -----------------------------------------------------
	# Controlled smoke-test baseline.
	# -----------------------------------------------------
	game.stop_game_flow()
	game.game_has_ended = false
	game.clear_player_input()
	game.resolution_stack.clear()
	game.processing_resolution_stack = false
	game.trigger_window_active = false
	game.trigger_window_queue.clear()
	game.trigger_window_stack.clear()
	game.current_phase_play_order.clear()
	game.current_phase = ""
	game.current_round = 1
	game.current_moon = 1
	game.black_rose_power = 0
	game.starting_setup_complete = false
	game.starting_setup_order.clear()
	game.starting_setup_cursor = 0
	game.starting_setup_stage = "mage"
	game.create_school_libraries()

	for player_index in range(game.players.size()):
		var player = game.players[player_index]

		# Mage will be selected by the real setup pass.

		var saved_cell_room_id: String = player.mage.room_id
		var saved_cell_room_coord: Vector2i = player.mage.room_coord
		var saved_in_cell: bool = player.mage.in_cell

		player.mage_id = ""
		player.mage = MageState.new()
		player.mage.room_id = saved_cell_room_id
		player.mage.room_coord = saved_cell_room_coord
		player.mage.in_cell = saved_in_cell
		player.hand_limit = 6
		player.personal_spell_id = ""

		player.power = 0
		player.available_cubes = player.MAX_CUBES
		player.refresh_physical_actions()

		player.hand.clear()
		player.grimoire.clear()
		player.memories.clear()
		player.ready_spells.clear()
		player.quick_spell = null
		player.active_spells.clear()
		player.revealed_spells.clear()
		player.evocations.clear()
		player.active_quests.clear()
		player.completed_quests.clear()
		player.mage.damage_cubes.clear()

		player.personal_spell_copies_received = 0
		player.school_id = ""
		player.starting_grimoire_id = ""
		player.starting_grimoire_name = ""

		var entrance_room_id: String = str(
			game.player_entrance_room_ids.get(
				player_index,
				""
			)
		)

		if entrance_room_id == "":
			print("FAIL: full-turn smoke missing entrance Room")
			return false

		player.mage.room_id = entrance_room_id
		player.mage.room_coord = game.room_id_to_coord(
			entrance_room_id
		)
		player.mage.in_cell = true

	# Ensure there is enough public content for one complete Study Phase.
	if game.active_school_ids.size() < 2:
		print("FAIL: full-turn smoke needs at least two active Schools")
		return false

	var starting_round: int = game.current_round

	if not game.start_game_flow():
		print("FAIL: start_game_flow() failed")
		return false

	var submitted_inputs: int = 0
	var max_inputs: int = 300

	while game.current_round == starting_round \
	and submitted_inputs < max_inputs:

		if not game.waiting_for_player_input:
			# The full flow should either be resolving synchronously or waiting
			# for a player decision. With an empty resolution stack, no pending
			# input means the phase machine stalled.
			if game.resolution_stack.is_empty():
				print(
					"FAIL: full-turn flow stalled in phase ",
					game.current_phase
				)
				return false

			if not game.process_resolution_stack():
				print("FAIL: resolution stack failed during smoke")
				return false

			continue

		var request: Dictionary = game.pending_input.duplicate(true)
		var input_type: String = str(
			request.get("type", "")
		)
		var request_player: int = int(
			request.get("player_index", -1)
		)

		var payload: Dictionary = _beta_smoke_payload(
			game,
			request
		)

		if payload.is_empty():
			print(
				"FAIL: smoke driver has no legal payload for ",
				input_type,
				" | Player ",
				request_player + 1
			)
			return false

		if not game.submit_beta_input(
			request_player,
			payload
		):
			print(
				"FAIL: beta input rejected during full-turn smoke | ",
				input_type,
				" | Player ",
				request_player + 1
			)
			return false

		submitted_inputs += 1

	if submitted_inputs >= max_inputs:
		print("FAIL: full-turn smoke exceeded input safety limit")
		return false

	if game.current_round != starting_round + 1:
		print(
			"FAIL: full-turn smoke did not advance exactly one Round | ",
			game.current_round
		)
		return false

	# Cleanly stop the automatic loop after proving the Clean-up -> next Round
	# boundary. The next Black Rose Phase may already have requested its first
	# input synchronously.
	game.stop_game_flow()
	game.clear_player_input()
	game.resolution_stack.clear()
	game.trigger_window_active = false
	game.trigger_window_queue.clear()
	game.trigger_window_stack.clear()

	print(
		"PASS: full Turn crossed Black Rose -> Study -> Preparation -> ",
		"Action -> Evocation -> Clean-up -> next Round | inputs=",
		submitted_inputs
	)
	return true


static func _test_beta_legal_actions_v13(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V13 legal-actions test needs at least two players")
		return false

	var player = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_in_cell: bool = player.mage.in_cell
	var saved_room_id: String = player.mage.room_id
	var saved_room_coord: Vector2i = player.mage.room_coord
	var saved_opponent_in_cell: bool = opponent.mage.in_cell
	var saved_opponent_room_id: String = opponent.mage.room_id
	var saved_opponent_room_coord: Vector2i = opponent.mage.room_coord
	var saved_actions: int = player.available_physical_actions
	var saved_ready: Array[ReadySpellState] = player.ready_spells.duplicate()
	var saved_quick: ReadySpellState = player.quick_spell
	var saved_evocations: Array[EvocationState] = player.evocations.duplicate()
	var saved_completed_quests: Array[QuestState] = player.completed_quests.duplicate()

	player.ready_spells.clear()
	player.quick_spell = null
	player.evocations.clear()
	player.completed_quests.clear()
	player.available_physical_actions = player.MAX_PHYSICAL_ACTIONS

	var test_spell := SpellCardState.new(
		"v13_legal_test",
		"V13 Legal Test",
		"agony",
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		},
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		}
	)

	player.ready_spells.append(
		ReadySpellState.new(
			test_spell,
			false
		)
	)

	var entrance_room_id: String = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)

	if entrance_room_id == "":
		print("FAIL: V13 legal-actions test missing entrance Room")
		return false

	# -----------------------------------------------------
	# 1) Cell: only actions that can legally operate from the Cell.
	# -----------------------------------------------------
	player.mage.in_cell = true
	player.mage.room_id = entrance_room_id
	player.mage.room_coord = game.room_id_to_coord(
		entrance_room_id
	)

	var cell_legal: Dictionary = game.get_beta_legal_actions(
		player_index
	)

	if cell_legal.get("cast", []).size() != 0:
		print("FAIL: Cast action exposed while Mage is in Cell")
		return false

	if cell_legal.get("fight", []).size() != 0:
		print("FAIL: Fight action exposed while Mage is in Cell")
		return false

	if cell_legal.get("command", []).size() != 0:
		print("FAIL: Command action exposed while Mage is in Cell")
		return false

	if cell_legal.get("quests", []).size() != 0:
		print("FAIL: Completed Quest exposed while Mage is in Cell")
		return false

	var cell_momentum: Array = cell_legal.get(
		"momentum",
		[]
	)

	if cell_momentum.is_empty():
		print("FAIL: Momentum missing while Ready Spell exists in Cell")
		return false

	for option_value in cell_momentum:
		var option: Dictionary = option_value
		if str(option.get("destination_room_id", "")) != entrance_room_id:
			print("FAIL: Cell Momentum offered an illegal destination")
			return false

	var cell_explore: Array = cell_legal.get(
		"explore",
		[]
	)

	if cell_explore.is_empty():
		print("FAIL: Explore missing while Mage can leave Cell")
		return false

	for option_value in cell_explore:
		var option: Dictionary = option_value
		var path: Array = option.get("path", [])

		if path.is_empty() \
		or str(path[0]) != entrance_room_id:
			print("FAIL: Cell Explore does not start at entrance Room")
			return false

		if path.size() > player.mage.speed:
			print("FAIL: Cell Explore path exceeds Mage Speed")
			return false

	# -----------------------------------------------------
	# 2) Lodge: Cast/Momentum/Explore/Fight/Command/Quest are derived from
	#    actual state without mutating that state.
	# -----------------------------------------------------
	player.mage.in_cell = false
	player.mage.room_id = entrance_room_id
	player.mage.room_coord = game.room_id_to_coord(
		entrance_room_id
	)

	opponent.mage.in_cell = false
	opponent.mage.room_id = entrance_room_id
	opponent.mage.room_coord = player.mage.room_coord

	var test_evocation := EvocationState.new(
		"v13_command_test",
		"V13 Command Test",
		"construct",
		3,
		1,
		1,
		player_index
	)
	test_evocation.room_id = entrance_room_id
	player.evocations.append(test_evocation)

	var test_quest_card := QuestCardState.new(
		"v13_completed_quest",
		"V13 Completed Quest",
		1,
		{},
		[],
		0,
		1
	)
	var test_quest := QuestState.new(
		test_quest_card,
		player_index
	)
	test_quest.complete()
	player.completed_quests.append(test_quest)

	var before_room: String = player.mage.room_id
	var before_ready_count: int = player.ready_spells.size()
	var before_actions: int = player.available_physical_actions
	var before_memory_count: int = player.memories.size()

	var lodge_legal: Dictionary = game.get_beta_legal_actions(
		player_index
	)

	if lodge_legal.get("cast", []).is_empty():
		print("FAIL: legal Cast missing in Lodge")
		return false

	if lodge_legal.get("momentum", []).is_empty():
		print("FAIL: legal Momentum missing in Lodge")
		return false

	if lodge_legal.get("explore", []).is_empty():
		print("FAIL: legal Explore missing in Lodge")
		return false

	if lodge_legal.get("fight", []).is_empty():
		print("FAIL: legal Fight missing in Lodge")
		return false

	var command_options: Array = lodge_legal.get(
		"command",
		[]
	)

	if command_options.is_empty():
		print("FAIL: Command options missing for owned Evocation")
		return false

	for command_value in command_options:
		var command_option: Dictionary = command_value
		var command_action: Dictionary = command_option.get(
			"action",
			{}
		)

		if int(
			command_action.get(
				"evocation_index",
				-1
			)
		) != 0:
			print("FAIL: Command option points to wrong Evocation")
			return false

	if lodge_legal.get("quests", []).size() != 1:
		print("FAIL: Completed Quest missing from legal timing options")
		return false

	var found_opponent_attack: bool = false

	for option_value in lodge_legal.get("fight", []):
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})

		if bool(action.get("perform_attack", false)) \
		and int(action.get("target_player_index", -1)) == opponent_index:
			found_opponent_attack = true
			break

	if not found_opponent_attack:
		print("FAIL: Fight did not expose Mage in same Room")
		return false

	# Explore paths must be composed exclusively of adjacent Room transitions.
	for option_value in lodge_legal.get("explore", []):
		var option: Dictionary = option_value
		var path: Array = option.get("path", [])
		var previous_room_id: String = entrance_room_id

		if path.size() > player.mage.speed:
			print("FAIL: Lodge Explore path exceeds Mage Speed")
			return false

		for room_value in path:
			var room_id: String = str(room_value)

			if not game._beta_adjacent_room_ids(
				previous_room_id
			).has(room_id):
				print("FAIL: Explore API generated non-adjacent movement")
				return false

			previous_room_id = room_id

	# Querying legal actions must be pure.
	if player.mage.room_id != before_room \
	or player.ready_spells.size() != before_ready_count \
	or player.available_physical_actions != before_actions \
	or player.memories.size() != before_memory_count:
		print("FAIL: legal-actions query mutated gameplay state")
		return false

	# The action request itself must carry the same API for the UI.
	game.pending_input = {
		"type": "action_activation",
		"player_index": player_index,
		"legal_actions": lodge_legal
	}
	game.waiting_for_player_input = true

	var request_state: Dictionary = game.get_beta_pending_input(
		player_index
	)

	if not request_state.has("legal_actions"):
		print("FAIL: action_activation request does not expose legal_actions")
		return false

	game.clear_player_input()

	# Restore state.
	player.mage.in_cell = saved_in_cell
	player.mage.room_id = saved_room_id
	player.mage.room_coord = saved_room_coord

	opponent.mage.in_cell = saved_opponent_in_cell
	opponent.mage.room_id = saved_opponent_room_id
	opponent.mage.room_coord = saved_opponent_room_coord

	player.available_physical_actions = saved_actions

	player.ready_spells.clear()
	player.ready_spells.append_array(saved_ready)
	player.quick_spell = saved_quick

	player.evocations.clear()
	player.evocations.append_array(saved_evocations)

	player.completed_quests.clear()
	player.completed_quests.append_array(saved_completed_quests)

	print("PASS: legal-actions API exposes UI-ready actions without mutating game state")
	return true


static func _test_physical_attack_models_v14(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V14 physical combat test needs at least two players")
		return false

	var attacker = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_attacker_room: String = attacker.mage.room_id
	var saved_attacker_coord: Vector2i = attacker.mage.room_coord
	var saved_attacker_cell: bool = attacker.mage.in_cell
	var saved_attacker_strength: int = attacker.mage.strength
	var saved_attacker_actions: int = attacker.available_physical_actions
	var saved_attacker_cubes: int = attacker.available_cubes

	var saved_opponent_room: String = opponent.mage.room_id
	var saved_opponent_coord: Vector2i = opponent.mage.room_coord
	var saved_opponent_cell: bool = opponent.mage.in_cell

	var saved_attacker_evocations: Array[EvocationState] = (
		attacker.evocations.duplicate()
	)
	var saved_opponent_evocations: Array[EvocationState] = (
		opponent.evocations.duplicate()
	)

	var room_id: String = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)

	if room_id == "":
		print("FAIL: V14 test missing Lodge Room")
		return false

	attacker.mage.in_cell = false
	attacker.mage.room_id = room_id
	attacker.mage.room_coord = game.room_id_to_coord(room_id)
	attacker.mage.strength = 2
	attacker.available_physical_actions = attacker.MAX_PHYSICAL_ACTIONS

	opponent.mage.in_cell = false
	opponent.mage.room_id = room_id
	opponent.mage.room_coord = attacker.mage.room_coord

	attacker.evocations.clear()
	opponent.evocations.clear()

	var enemy_evocation := EvocationState.new(
		"v14_enemy",
		"V14 Enemy",
		"construct",
		4,
		1,
		1,
		opponent_index
	)
	enemy_evocation.controller_id = opponent_index
	enemy_evocation.room_id = room_id
	opponent.evocations.append(enemy_evocation)

	var controlled_evocation := EvocationState.new(
		"v14_controlled",
		"V14 Controlled",
		"construct",
		4,
		1,
		1,
		opponent_index
	)
	controlled_evocation.controller_id = player_index
	controlled_evocation.room_id = room_id
	opponent.evocations.append(controlled_evocation)

	# -----------------------------------------------------
	# 1) Legal Fight targets include enemy Mage + enemy Evocation,
	#    but not an Evocation controlled by the attacker.
	# -----------------------------------------------------
	var legal: Dictionary = game.get_beta_legal_actions(
		player_index
	)

	var fight_options: Array = legal.get("fight", [])
	var found_mage: bool = false
	var found_enemy_evocation: bool = false
	var found_controlled_evocation: bool = false
	var enemy_action: Dictionary = {}

	for option_value in fight_options:
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})

		if not bool(action.get("perform_attack", false)):
			continue

		var target_type: String = str(
			action.get("target_model_type", "")
		)

		if target_type == "mage" \
		and int(action.get("target_player_index", -1)) == opponent_index:
			found_mage = true

		if target_type == "evocation":
			var evocation_index: int = int(
				action.get(
					"target_evocation_index",
					-1
				)
			)

			if evocation_index == 0:
				found_enemy_evocation = true

				if not bool(
					action.get(
						"perform_room_activation",
						false
					)
				):
					enemy_action = action.duplicate(true)

			if evocation_index == 1:
				found_controlled_evocation = true

	if not found_mage:
		print("FAIL: Fight API lost legal Mage target")
		return false

	if not found_enemy_evocation:
		print("FAIL: Fight API missing enemy Evocation target")
		return false

	if found_controlled_evocation:
		print("FAIL: Fight API exposed Evocation controlled by attacker")
		return false

	if enemy_action.is_empty():
		print("FAIL: no attack-only Evocation Fight action found")
		return false

	# -----------------------------------------------------
	# 2) Physical Attack deals Strength Damage to the selected Evocation,
	#    consumes one Physical Action and Damage Cubes.
	# -----------------------------------------------------
	var cubes_before: int = attacker.available_cubes
	var actions_before: int = attacker.available_physical_actions

	if not game.perform_player_action(
		player_index,
		enemy_action
	):
		print("FAIL: Evocation Physical Attack did not start")
		return false

	if enemy_evocation.get_damage() != 2:
		print(
			"FAIL: Evocation expected 2 Physical Attack Damage, got ",
			enemy_evocation.get_damage()
		)
		return false

	if attacker.available_cubes != cubes_before - 2:
		print("FAIL: Evocation Damage did not consume attacker Cubes")
		return false

	if attacker.available_physical_actions != actions_before - 1:
		print("FAIL: Fight did not exhaust one Physical Action")
		return false

	if controlled_evocation.get_damage() != 0:
		print("FAIL: controlled Evocation was damaged unexpectedly")
		return false

	# Heal the synthetic Damage manually before the defeat-removal test.
	while not enemy_evocation.damage_cubes.is_empty():
		var cube_owner: int = int(enemy_evocation.damage_cubes.pop_back())
		game.return_owner_cubes(cube_owner, 1)

	# -----------------------------------------------------
	# 3) Defeated Evocation leaves play, frees its slot, and its Damage
	#    Cubes return to their owner.
	# -----------------------------------------------------
	var weak_evocation := EvocationState.new(
		"v14_weak",
		"V14 Weak",
		"demon",
		1,
		1,
		1,
		opponent_index
	)
	weak_evocation.controller_id = opponent_index
	weak_evocation.room_id = room_id
	opponent.evocations.append(weak_evocation)

	attacker.available_physical_actions = 1
	cubes_before = attacker.available_cubes

	var weak_action: Dictionary = {
		"type": "fight",
		"target_model_type": "evocation",
		"target_player_index": -1,
		"target_evocation_owner_id": opponent_index,
		"target_evocation_index": opponent.evocations.find(weak_evocation),
		"activate_room_first": false,
		"perform_attack": true,
		"perform_room_activation": false
	}

	if not game.perform_player_action(
		player_index,
		weak_action
	):
		print("FAIL: defeating Physical Attack did not start")
		return false

	if opponent.evocations.has(weak_evocation):
		print("FAIL: defeated Evocation remained in play")
		return false

	if attacker.available_cubes != cubes_before:
		print("FAIL: Damage Cubes were not returned after Evocation defeat")
		return false

	# -----------------------------------------------------
	# Restore state.
	# -----------------------------------------------------
	attacker.mage.room_id = saved_attacker_room
	attacker.mage.room_coord = saved_attacker_coord
	attacker.mage.in_cell = saved_attacker_cell
	attacker.mage.strength = saved_attacker_strength
	attacker.available_physical_actions = saved_attacker_actions
	attacker.available_cubes = saved_attacker_cubes

	opponent.mage.room_id = saved_opponent_room
	opponent.mage.room_coord = saved_opponent_coord
	opponent.mage.in_cell = saved_opponent_cell

	attacker.evocations.clear()
	attacker.evocations.append_array(saved_attacker_evocations)

	opponent.evocations.clear()
	opponent.evocations.append_array(saved_opponent_evocations)

	print("PASS: Fight attacks Mage/Evocation Models and removes defeated Evocations correctly")
	return true


static func _test_evocation_activation_v15(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V15 Evocation test needs at least two players")
		return false

	var controller = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_controller_room: String = controller.mage.room_id
	var saved_controller_coord: Vector2i = controller.mage.room_coord
	var saved_controller_cell: bool = controller.mage.in_cell
	var saved_controller_actions: int = controller.available_physical_actions
	var saved_controller_cubes: int = controller.available_cubes

	var saved_opponent_room: String = opponent.mage.room_id
	var saved_opponent_coord: Vector2i = opponent.mage.room_coord
	var saved_opponent_cell: bool = opponent.mage.in_cell

	var saved_controller_evocations: Array[EvocationState] = (
		controller.evocations.duplicate()
	)
	var saved_opponent_evocations: Array[EvocationState] = (
		opponent.evocations.duplicate()
	)

	var origin_room_id: String = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)

	if origin_room_id == "":
		print("FAIL: V15 missing origin Room")
		return false

	var adjacent_rooms: Array[String] = game._beta_adjacent_room_ids(
		origin_room_id
	)

	if adjacent_rooms.is_empty():
		print("FAIL: V15 origin Room has no adjacent Room")
		return false

	var destination_room_id: String = adjacent_rooms[0]

	controller.mage.in_cell = false
	controller.mage.room_id = origin_room_id
	controller.mage.room_coord = game.room_id_to_coord(
		origin_room_id
	)
	controller.available_physical_actions = controller.MAX_PHYSICAL_ACTIONS

	opponent.mage.in_cell = false
	opponent.mage.room_id = origin_room_id
	opponent.mage.room_coord = controller.mage.room_coord

	controller.evocations.clear()
	opponent.evocations.clear()

	var attacker := EvocationState.new(
		"v15_attacker",
		"V15 Attacker",
		"construct",
		4,
		2,
		2,
		player_index
	)
	attacker.controller_id = player_index
	attacker.room_id = origin_room_id
	controller.evocations.append(attacker)

	var enemy_origin := EvocationState.new(
		"v15_enemy_origin",
		"V15 Enemy Origin",
		"demon",
		5,
		1,
		1,
		opponent_index
	)
	enemy_origin.controller_id = opponent_index
	enemy_origin.room_id = origin_room_id
	opponent.evocations.append(enemy_origin)

	var enemy_destination := EvocationState.new(
		"v15_enemy_destination",
		"V15 Enemy Destination",
		"demon",
		5,
		1,
		1,
		opponent_index
	)
	enemy_destination.controller_id = opponent_index
	enemy_destination.room_id = destination_room_id
	opponent.evocations.append(enemy_destination)

	var friendly_controlled := EvocationState.new(
		"v15_friendly_controlled",
		"V15 Friendly Controlled",
		"demon",
		5,
		1,
		1,
		opponent_index
	)
	friendly_controlled.controller_id = player_index
	friendly_controlled.room_id = origin_room_id
	opponent.evocations.append(friendly_controlled)

	# -----------------------------------------------------
	# 1) Generated plans obey Move...Move -> Attack / Attack -> Move...Move.
	# -----------------------------------------------------
	var plans: Array = game._beta_evocation_activation_plans(
		attacker,
		player_index
	)

	if plans.is_empty():
		print("FAIL: no Evocation activation plans generated")
		return false

	var found_attack_before: bool = false
	var found_attack_after: bool = false
	var found_friendly_target: bool = false
	var command_after_action: Dictionary = {}

	for plan_value in plans:
		var plan: Dictionary = plan_value
		var context: Dictionary = plan.get("context", {})
		var target: Dictionary = plan.get("target", {})
		var timing: String = str(
			context.get(
				"evocation_attack_timing",
				"none"
			)
		)

		if str(target.get("name", "")) == "V15 Friendly Controlled":
			found_friendly_target = true

		if timing == "before" \
		and str(target.get("name", "")) == "V15 Enemy Origin":
			found_attack_before = true

		if timing == "after" \
		and str(target.get("name", "")) == "V15 Enemy Destination" \
		and context.get("evocation_move_room_ids", []).size() == 1 \
		and str(context.get("evocation_move_room_ids", [])[0]) == destination_room_id:
			found_attack_after = true

	if not found_attack_before:
		print("FAIL: missing attack-before-movement plan")
		return false

	if not found_attack_after:
		print("FAIL: missing move-then-attack plan")
		return false

	if found_friendly_target:
		print("FAIL: Evocation could attack Model controlled by its controller")
		return false

	# -----------------------------------------------------
	# 2) Command Legal Actions embed the complete activation context.
	# -----------------------------------------------------
	var legal: Dictionary = game.get_beta_legal_actions(
		player_index
	)

	for option_value in legal.get("command", []):
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})
		var context: Dictionary = action.get("context", {})

		if int(action.get("evocation_index", -1)) != 0:
			continue

		if str(
			context.get(
				"evocation_attack_timing",
				""
			)
		) != "after":
			continue

		var path: Array = context.get(
			"evocation_move_room_ids",
			[]
		)

		if path.size() != 1 \
		or str(path[0]) != destination_room_id:
			continue

		if str(
			context.get(
				"evocation_target_model_type",
				""
			)
		) != "evocation":
			continue

		var target_owner: int = int(
			context.get(
				"evocation_target_evocation_owner_id",
				-1
			)
		)
		var target_index: int = int(
			context.get(
				"evocation_target_evocation_index",
				-1
			)
		)

		if game.get_evocation_by_owner_index(
			target_owner,
			target_index
		) == enemy_destination:
			command_after_action = action.duplicate(true)
			break

	if command_after_action.is_empty():
		print("FAIL: Command did not expose move-then-attack plan")
		return false

	# -----------------------------------------------------
	# 3) Command consumes Physical Action, moves, and attacks the selected
	#    Evocation using the controller's Cubes.
	# -----------------------------------------------------
	var cubes_before: int = controller.available_cubes
	var actions_before: int = controller.available_physical_actions

	if not game.perform_player_action(
		player_index,
		command_after_action
	):
		print("FAIL: Command activation did not start")
		return false

	if attacker.room_id != destination_room_id:
		print("FAIL: commanded Evocation did not follow movement path")
		return false

	if enemy_destination.get_damage() != attacker.strength:
		print(
			"FAIL: commanded Evocation attack expected ",
			attacker.strength,
			" Damage, got ",
			enemy_destination.get_damage()
		)
		return false

	if controller.available_cubes != cubes_before - attacker.strength:
		print("FAIL: Evocation attack did not consume controller Cubes")
		return false

	if controller.available_physical_actions != actions_before - 1:
		print("FAIL: Command did not exhaust Physical Action")
		return false

	# Return synthetic target Damage before later checks.
	while not enemy_destination.damage_cubes.is_empty():
		var cube_owner: int = int(
			enemy_destination.damage_cubes.pop_back()
		)
		game.return_owner_cubes(
			cube_owner,
			1
		)

	# Reset attacker to origin.
	attacker.room_id = origin_room_id

	# -----------------------------------------------------
	# 4) Evocation Phase requests expose the same legal plan API.
	# -----------------------------------------------------
	var phase_plans: Array = game._beta_evocation_activation_plans(
		attacker,
		game.get_evocation_controller_id(attacker)
	)

	if phase_plans.is_empty():
		print("FAIL: Evocation Phase has no activation plans")
		return false

	var valid_plan: Dictionary = phase_plans[0]
	var valid_context: Dictionary = valid_plan.get(
		"context",
		{}
	)

	if not game._validate_evocation_activation_context(
		attacker,
		player_index,
		valid_context
	):
		print("FAIL: generated Evocation plan fails its own validator")
		return false

	var invalid_context: Dictionary = {
		"evocation_attack_timing": "after",
		"evocation_move_room_ids": [
			destination_room_id,
			origin_room_id,
			destination_room_id
		]
	}

	if game._validate_evocation_activation_context(
		attacker,
		player_index,
		invalid_context
	):
		print("FAIL: Evocation validator accepted path beyond Speed")
		return false

	# -----------------------------------------------------
	# Restore state.
	# -----------------------------------------------------
	controller.mage.room_id = saved_controller_room
	controller.mage.room_coord = saved_controller_coord
	controller.mage.in_cell = saved_controller_cell
	controller.available_physical_actions = saved_controller_actions
	controller.available_cubes = saved_controller_cubes

	opponent.mage.room_id = saved_opponent_room
	opponent.mage.room_coord = saved_opponent_coord
	opponent.mage.in_cell = saved_opponent_cell

	controller.evocations.clear()
	controller.evocations.append_array(saved_controller_evocations)

	opponent.evocations.clear()
	opponent.evocations.append_array(saved_opponent_evocations)

	print("PASS: Command and Evocation Phase expose complete Move/Attack activation plans")
	return true


static func _test_stepwise_activation_v16(
	game,
	player_index: int
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V16 stepwise test needs at least two players")
		return false

	var player = game.players[player_index]
	var opponent_index: int = 1 if player_index == 0 else 0
	var opponent = game.players[opponent_index]

	var saved_phase: String = game.current_phase
	var saved_waiting: bool = game.waiting_for_player_input
	var saved_pending: Dictionary = game.pending_input.duplicate(true)
	var saved_play_order: Array[int] = game.current_phase_play_order.duplicate()
	var saved_cursor: int = game.action_phase_cursor
	var saved_round: int = game.action_phase_activation_round

	var saved_player_room: String = player.mage.room_id
	var saved_player_coord: Vector2i = player.mage.room_coord
	var saved_player_cell: bool = player.mage.in_cell
	var saved_player_actions: int = player.available_physical_actions

	var saved_opponent_room: String = opponent.mage.room_id
	var saved_opponent_coord: Vector2i = opponent.mage.room_coord
	var saved_opponent_cell: bool = opponent.mage.in_cell

	game.clear_player_input()
	game._reset_stepwise_action_activation()

	var origin_room_id: String = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)

	if origin_room_id == "":
		print("FAIL: V16 missing origin Room")
		return false

	var adjacent_rooms: Array[String] = game._beta_adjacent_room_ids(
		origin_room_id
	)

	if adjacent_rooms.is_empty():
		print("FAIL: V16 origin Room has no adjacent Room")
		return false

	var destination_room_id: String = adjacent_rooms[0]

	player.mage.in_cell = false
	player.mage.room_id = origin_room_id
	player.mage.room_coord = game.room_id_to_coord(
		origin_room_id
	)
	player.available_physical_actions = 2

	opponent.mage.in_cell = false
	opponent.mage.room_id = destination_room_id
	opponent.mage.room_coord = game.room_id_to_coord(
		destination_room_id
	)

	game.current_phase = game.PHASE_ACTION
	game.current_phase_play_order.clear()
	game.current_phase_play_order.append_array(
		[
			player_index,
			opponent_index
		] as Array[int]
	)
	game.action_phase_cursor = 1
	game.action_phase_activation_round = 1

	if not game._start_stepwise_action_activation(
		player_index
	):
		print("FAIL: could not start stepwise Activation")
		return false

	if str(
		game.pending_input.get(
			"type",
			""
		)
	) != "action_activation_step":
		print("FAIL: stepwise Activation did not request an Action step")
		return false

	# Opponent is not in the origin Room, so Fight must not yet be offered.
	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})

		if str(action.get("type", "")) == "fight" \
		and bool(action.get("perform_attack", false)) \
		and int(
			action.get(
				"target_player_index",
				-1
			)
		) == opponent_index:
			print("FAIL: Fight target exposed before Explore")
			return false

	# Choose a one-Room Explore into the opponent's Room.
	var explore_token: String = ""

	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})

		if str(action.get("type", "")) != "explore":
			continue

		if bool(
			action.get(
				"activate_room_before_movement",
				false
			)
		) \
		or bool(
			action.get(
				"activate_room_after_movement",
				false
			)
		):
			continue

		var path: Array = action.get(
			"destination_room_ids",
			[]
		)

		if path.size() == 1 \
		and str(path[0]) == destination_room_id:
			explore_token = str(
				option.get(
					"token",
					""
				)
			)
			break

	if explore_token == "":
		print("FAIL: no legal Explore token found for V16")
		return false

	if not game.submit_action_activation_step(
		player_index,
		explore_token
	):
		print("FAIL: first stepwise Action was rejected")
		return false

	if player.mage.room_id != destination_room_id:
		print("FAIL: first Action did not update board state")
		return false

	if not game.waiting_for_player_input \
	or str(
		game.pending_input.get(
			"type",
			""
		)
	) != "action_activation_step":
		print("FAIL: Action 2 was not requested after Action 1")
		return false

	if int(
		game.pending_input.get(
			"actions_used",
			-1
		)
	) != 1:
		print("FAIL: stepwise Activation did not track Action count")
		return false

	# The SECOND request is recomputed after movement and must now contain
	# the opponent as a legal Fight target.
	var found_dynamic_fight: bool = false
	var found_finish: bool = false

	for option_value in game.pending_input.get("options", []):
		var option: Dictionary = option_value
		var action: Dictionary = option.get("action", {})

		if str(option.get("kind", "")) == "finish":
			found_finish = true

		if str(action.get("type", "")) == "fight" \
		and bool(action.get("perform_attack", false)) \
		and int(
			action.get(
				"target_player_index",
				-1
			)
		) == opponent_index:
			found_dynamic_fight = true

	if not found_dynamic_fight:
		print("FAIL: Action 2 legality was not recomputed after movement")
		return false

	if not found_finish:
		print("FAIL: player cannot end Activation after one Action")
		return false

	# Clean up the isolated test without advancing the real phase loop.
	game.clear_player_input()
	game._reset_stepwise_action_activation()

	player.mage.room_id = saved_player_room
	player.mage.room_coord = saved_player_coord
	player.mage.in_cell = saved_player_cell
	player.available_physical_actions = saved_player_actions

	opponent.mage.room_id = saved_opponent_room
	opponent.mage.room_coord = saved_opponent_coord
	opponent.mage.in_cell = saved_opponent_cell

	game.current_phase = saved_phase
	game.current_phase_play_order.clear()
	game.current_phase_play_order.append_array(saved_play_order)
	game.action_phase_cursor = saved_cursor
	game.action_phase_activation_round = saved_round

	if saved_waiting:
		game.pending_input = saved_pending
		game.waiting_for_player_input = true

	print("PASS: Action 2 legal choices are recomputed after Action 1 changes the board")
	return true


static func _test_beta_hud_contract_v17(
	game
) -> bool:
	var hud = BetaHUDScript.new()

	var engine_types: Array[String] = (
		game.get_beta_supported_input_types()
	)
	var hud_types: Array[String] = (
		hud.get_supported_input_types()
	)

	for input_type in engine_types:
		if not hud_types.has(input_type):
			print(
				"FAIL: Beta HUD does not support engine input type ",
				input_type
			)
			hud.free()
			return false

	var required_normal_flow: Array[String] = [
		"starting_mage_choice",
		"starting_school_choice",
		"starting_grimoire_choice",
		"action_activation_step",
		"effect_choice",
		"preparation",
		"study_choose_schools",
		"study_keep_cards",
		"study_optional_discard",
		"study_hand_limit",
		"trigger_decision",
		"evocation_phase_activations",
		"cleanup_active_spells",
		"black_rose_optional_quest_discard",
		"black_rose_active_quest_limit",
		"black_rose_completed_quest_limit"
	]

	for input_type in required_normal_flow:
		if not hud.supports_input_type(input_type):
			print(
				"FAIL: Beta HUD missing normal-flow input ",
				input_type
			)
			hud.free()
			return false

	hud.free()

	print("PASS: Beta HUD covers every current engine input contract")
	return true


static func _test_beta_hud_grouping_v18() -> bool:
	var hud = BetaHUDScript.new()

	var synthetic_request: Dictionary = {
		"options": [
			{
				"token": "action:0",
				"kind": "action",
				"label": "Explore",
				"action": {
					"type": "explore",
					"destination_room_ids": ["garden"]
				}
			},
			{
				"token": "action:1",
				"kind": "action",
				"label": "Explore + activate Room",
				"action": {
					"type": "explore",
					"destination_room_ids": ["garden"],
					"activate_room_after_movement": true
				}
			},
			{
				"token": "action:2",
				"kind": "action",
				"label": "Momentum: discard Test Spell",
				"action": {
					"type": "momentum",
					"ready_index": 0,
					"use_quick": false,
					"destination_room_id": "garden"
				}
			},
			{
				"token": "action:3",
				"kind": "action",
				"label": "Momentum: discard Test Spell",
				"action": {
					"type": "momentum",
					"ready_index": 0,
					"use_quick": false,
					"destination_room_id": "arena"
				}
			}
		]
	}

	var entries: Array = hud.get_action_root_entries_for_request(
		synthetic_request
	)

	var explore_count: int = 0
	var momentum_count: int = 0

	for entry_value in entries:
		var entry: Dictionary = entry_value
		var key: String = str(entry.get("key", ""))

		if key == "explore":
			explore_count += 1

		if key.begins_with("momentum:"):
			momentum_count += 1

	hud.free()

	if explore_count != 1:
		print("FAIL: HUD still duplicates Explore on root menu")
		return false

	if momentum_count != 1:
		print("FAIL: HUD still duplicates Momentum per destination")
		return false

	print("PASS: Action HUD groups variants and asks movement target in a second step")
	return true


static func _test_room_target_choice_v18(
	game,
	player_index: int
) -> bool:
	var saved_waiting: bool = game.waiting_for_player_input
	var saved_pending: Dictionary = game.pending_input.duplicate(true)

	game.clear_player_input()

	var room = game.get_room_by_id(
		"alchemical_laboratory"
	)

	if room == null:
		print("FAIL: Alchemical Laboratory missing")
		return false

	var effects: Array = room.get_effects()

	if effects.is_empty():
		print("FAIL: Alchemical Laboratory has no current-side Effect")
		return false

	var damage_effect: Dictionary = effects[0]

	if str(damage_effect.get("type", "")) == "damage":
		if str(damage_effect.get("target", "")) != "room" \
		or int(damage_effect.get("range", -1)) != 1:
			print("FAIL: Alchemical Laboratory is not Room range 1")
			return false

	var player = game.players[player_index]
	var saved_room: String = player.mage.room_id
	var saved_coord: Vector2i = player.mage.room_coord
	var saved_cell: bool = player.mage.in_cell

	player.mage.in_cell = false
	player.mage.room_id = "alchemical_laboratory"
	player.mage.room_coord = game.room_id_to_coord(
		"alchemical_laboratory"
	)

	var context: Dictionary = {
		"game": game,
		"player_index": player_index,
		"caster_id": player_index,
		"room": room,
		"room_id": "alchemical_laboratory"
	}

	if game._prepare_room_effect_choice(
		damage_effect,
		context
	):
		print("FAIL: Room Area Effect did not request target")
		return false

	if not game.waiting_for_player_input \
	or str(game.pending_input.get("type", "")) != "effect_choice":
		print("FAIL: Room target did not use effect_choice")
		return false

	if str(
		game.pending_input.get(
			"choice_kind",
			""
		)
	) != "room_effect_room_target":
		print("FAIL: wrong Room target choice kind")
		return false

	if game.pending_input.get("options", []).is_empty():
		print("FAIL: Room target choice has no legal Rooms")
		return false

	game.pending_effect_choice_context = {}
	game.pending_effect_choice_values = {}
	game.clear_player_input()

	player.mage.room_id = saved_room
	player.mage.room_coord = saved_coord
	player.mage.in_cell = saved_cell

	if saved_waiting:
		game.pending_input = saved_pending
		game.waiting_for_player_input = true

	print("PASS: Room Area Effects request an explicit legal Room target")
	return true


static func _test_starting_grimoire_catalog_v19(
	game
) -> bool:
	var expected: Dictionary = {
		"agony": {
			"sadistic_fury": [
				"shared_torture",
				"grim_torment",
				"cross_and_delight",
				"torment",
				"visceral_fire",
				"peak_of_agony"
			],
			"algolagnia": [
				"pain_mark",
				"master_of_pleasure",
				"liquefy_the_pain",
				"submission",
				"ineluctable_pain",
				"heart_of_ice"
			]
		},
		"alchemy": {
			"scourge": [
				"azoth_bomb",
				"viatorium_spagyricum",
				"deflagrate",
				"athanor_eruption",
				"marbling",
				"stone_phoenix"
			],
			"auromancer": [
				"soul_transfer",
				"liquid_fire",
				"fountain_of_the_three",
				"purifying_aludel",
				"albify",
				"silver_of_the_sages"
			]
		}
	}

	for school_id in expected:
		if not game.school_specialization_database.has(
			school_id
		):
			print(
				"FAIL: missing Starting Grimoire School ",
				school_id
			)
			return false

		var school_data: Dictionary = (
			game.school_specialization_database[
				school_id
			]
		)
		var found: Dictionary = {}

		for grimoire_value in school_data.get(
			"starting_grimoires",
			[]
		):
			if not grimoire_value is Dictionary:
				continue

			var grimoire: Dictionary = grimoire_value
			found[
				str(
					grimoire.get(
						"id",
						""
					)
				)
			] = grimoire.get(
				"spell_ids",
				[]
			)

		for grimoire_id in expected[school_id]:
			if not found.has(grimoire_id):
				print(
					"FAIL: missing Starting Grimoire ",
					grimoire_id
				)
				return false

			if found[grimoire_id] != expected[
				school_id
			][grimoire_id]:
				print(
					"FAIL: wrong cards in ",
					grimoire_id
				)
				return false

	print("PASS: Agony and Alchemy Starting Grimoires match Codex catalog")
	return true


static func _test_cell_two_exits_v19(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	var exits: Array[String] = (
		game.get_player_cell_exit_room_ids(
			player_index
		)
	)

	if exits.size() != 2:
		print(
			"FAIL: Cell should have 2 Lodge exits, got ",
			exits
		)
		return false

	var saved_cell: bool = player.mage.in_cell
	var saved_room: String = player.mage.room_id
	var saved_coord: Vector2i = player.mage.room_coord
	var saved_actions: int = player.available_physical_actions
	var saved_ready: Array[ReadySpellState] = (
		player.ready_spells.duplicate()
	)
	var saved_quick: ReadySpellState = player.quick_spell

	player.mage.in_cell = true
	player.mage.room_id = str(
		game.player_entrance_room_ids.get(
			player_index,
			""
		)
	)
	player.mage.room_coord = Vector2i(
		game.player_entrance_room_coords.get(
			player_index,
			Vector2i.ZERO
		)
	)
	player.available_physical_actions = 2

	player.ready_spells.clear()
	player.quick_spell = null

	var test_spell := SpellCardState.new(
		"v19_cell_exit",
		"V19 Cell Exit",
		"agony",
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		},
		{
			"type": "combat",
			"element": "profane",
			"target": "model",
			"range": 1,
			"effects": []
		}
	)

	player.ready_spells.append(
		ReadySpellState.new(
			test_spell,
			false
		)
	)

	var legal: Dictionary = game.get_beta_legal_actions(
		player_index
	)

	var explore_first_rooms: Array[String] = []

	for option_value in legal.get("explore", []):
		var option: Dictionary = option_value
		var path: Array = option.get("path", [])

		if path.is_empty():
			continue

		var first_room: String = str(path[0])

		if not explore_first_rooms.has(first_room):
			explore_first_rooms.append(first_room)

	var momentum_rooms: Array[String] = []

	for option_value in legal.get("momentum", []):
		var option: Dictionary = option_value
		var destination: String = str(
			option.get(
				"destination_room_id",
				""
			)
		)

		if destination != "" \
		and not momentum_rooms.has(destination):
			momentum_rooms.append(destination)

	explore_first_rooms.sort()
	momentum_rooms.sort()

	var expected: Array[String] = exits.duplicate()
	expected.sort()

	player.mage.in_cell = saved_cell
	player.mage.room_id = saved_room
	player.mage.room_coord = saved_coord
	player.available_physical_actions = saved_actions
	player.ready_spells.clear()
	player.ready_spells.append_array(saved_ready)
	player.quick_spell = saved_quick

	if explore_first_rooms != expected:
		print(
			"FAIL: Explore Cell exits ",
			explore_first_rooms,
			" expected ",
			expected
		)
		return false

	if momentum_rooms != expected:
		print(
			"FAIL: Momentum Cell exits ",
			momentum_rooms,
			" expected ",
			expected
		)
		return false

	print("PASS: Explore and Momentum expose both Rooms adjacent to the Cell")
	return true


static func _test_command_ui_grouping_v19() -> bool:
	var hud = BetaHUDScript.new()

	var synthetic_request: Dictionary = {
		"options": [
			{
				"token": "action:0",
				"kind": "action",
				"action": {
					"type": "command",
					"evocation_index": 0,
					"context": {
						"evocation_move_room_ids": ["garden"],
						"evocation_attack_timing": "none"
					}
				},
				"descriptor": {
					"evocation": {"name": "Nigredo"}
				}
			},
			{
				"token": "action:1",
				"kind": "action",
				"action": {
					"type": "command",
					"evocation_index": 0,
					"context": {
						"evocation_move_room_ids": ["garden"],
						"evocation_attack_timing": "after"
					}
				},
				"descriptor": {
					"evocation": {"name": "Nigredo"}
				}
			},
			{
				"token": "action:2",
				"kind": "action",
				"action": {
					"type": "command",
					"evocation_index": 0,
					"context": {
						"evocation_move_room_ids": ["arena"],
						"evocation_attack_timing": "none"
					}
				},
				"descriptor": {
					"evocation": {"name": "Nigredo"}
				}
			}
		]
	}

	var roots: Array = hud.get_action_root_entries_for_request(
		synthetic_request
	)
	var command_count: int = 0

	for entry_value in roots:
		var entry: Dictionary = entry_value

		if str(
			entry.get(
				"key",
				""
			)
		).begins_with("command:"):
			command_count += 1

	hud.free()

	if command_count != 1:
		print("FAIL: Command still appears multiple times on Action root")
		return false

	print("PASS: Command UI has one root entry and separates movement from attack choice")
	return true


static func _test_starting_grimoire_build_v19(
	game,
	player_index: int
) -> bool:
	var player = game.players[player_index]

	var saved_school_id: String = player.school_id
	var saved_grimoire_id: String = player.starting_grimoire_id
	var saved_grimoire_name: String = player.starting_grimoire_name
	var saved_personal_count: int = player.personal_spell_copies_received

	var saved_hand: Array[SpellCardState] = player.hand.duplicate()
	var saved_grimoire: Array[SpellCardState] = player.grimoire.duplicate()
	var saved_memories: Array[SpellCardState] = player.memories.duplicate()
	var saved_ready: Array[ReadySpellState] = player.ready_spells.duplicate()
	var saved_quick: ReadySpellState = player.quick_spell
	var saved_active: Array[ActiveSpellState] = player.active_spells.duplicate()
	var saved_revealed: Array[RevealedSpellState] = player.revealed_spells.duplicate()

	var saved_libraries: Dictionary = game.school_libraries.duplicate(true)
	var saved_discards: Dictionary = game.school_discards.duplicate(true)

	game.create_school_libraries()

	player.school_id = "agony"
	player.starting_grimoire_id = ""
	player.starting_grimoire_name = ""
	player.personal_spell_copies_received = 0

	if not game.build_starting_grimoire(
		player_index,
		"agony",
		"sadistic_fury"
	):
		print("FAIL: could not build Sadistic Fury Starting Grimoire")
		return false

	var all_ids: Array[String] = []

	for spell in player.grimoire:
		all_ids.append(spell.id)

	for spell in player.memories:
		all_ids.append(spell.id)

	var expected_school_ids: Array[String] = [
		"shared_torture",
		"grim_torment",
		"cross_and_delight",
		"torment",
		"visceral_fire",
		"peak_of_agony"
	]

	for spell_id in expected_school_ids:
		if all_ids.count(spell_id) != 1:
			print(
				"FAIL: Starting Grimoire expected exactly one ",
				spell_id
			)
			return false

	if all_ids.count(player.personal_spell_id) != 1:
		print("FAIL: Starting Grimoire missing exactly one Personal Spell")
		return false

	if player.grimoire.size() != 6 \
	or player.memories.size() != 1:
		print(
			"FAIL: setup should leave 6-card Grimoire + 1 Memory, got ",
			player.grimoire.size(),
			" + ",
			player.memories.size()
		)
		return false

	# Restore all state.
	game.school_libraries = saved_libraries
	game.school_discards = saved_discards

	player.school_id = saved_school_id
	player.starting_grimoire_id = saved_grimoire_id
	player.starting_grimoire_name = saved_grimoire_name
	player.personal_spell_copies_received = saved_personal_count

	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.grimoire.clear()
	player.grimoire.append_array(saved_grimoire)
	player.memories.clear()
	player.memories.append_array(saved_memories)
	player.ready_spells.clear()
	player.ready_spells.append_array(saved_ready)
	player.quick_spell = saved_quick
	player.active_spells.clear()
	player.active_spells.append_array(saved_active)
	player.revealed_spells.clear()
	player.revealed_spells.append_array(saved_revealed)

	print("PASS: Starting Grimoire builds 6 School Spells + 1 Personal, with first card in Memories")
	return true


static func _test_beta_layout_native_scale_v20(
	game
) -> bool:
	var saved_enable: bool = game.enable_beta_hud
	var saved_run_tests: bool = game.run_tests_on_ready
	var saved_scale: Vector2 = game.scale
	var saved_position: Vector2 = game.position
	var saved_sidebar: float = game.beta_sidebar_width

	game.enable_beta_hud = true
	game.run_tests_on_ready = false
	game.beta_sidebar_width = 340.0
	game._apply_beta_table_layout()

	var ok: bool = (
		game.scale.is_equal_approx(
			Vector2.ONE
		)
		and game.position.is_equal_approx(
			Vector2.ZERO
		)
	)

	game.enable_beta_hud = saved_enable
	game.run_tests_on_ready = saved_run_tests
	game.beta_sidebar_width = saved_sidebar
	game.scale = saved_scale
	game.position = saved_position

	if not ok:
		print("FAIL: beta tabletop is still globally scaled down")
		return false

	print("PASS: beta tabletop stays at native scale and reserves only the HUD sidebar")
	return true


static func _test_specialization_fallback_v20(
	game
) -> bool:
	var fallback: Dictionary = (
		game._builtin_school_specializations()
	)

	for school_id in [
		"agony",
		"alchemy"
	]:
		if not fallback.has(school_id):
			print(
				"FAIL: built-in Starting Grimoire fallback missing ",
				school_id
			)
			return false

		var options: Array = fallback[
			school_id
		].get(
			"starting_grimoires",
			[]
		)

		if options.size() != 2:
			print(
				"FAIL: ",
				school_id,
				" fallback does not contain 2 Starting Grimoires"
			)
			return false

	print("PASS: interactive setup has a built-in Agony/Alchemy fallback and cannot stall on a missing JSON")
	return true


static func _test_mage_setup_pass_v21(
	game
) -> bool:
	if game.players.size() < 2:
		print("FAIL: V21 Mage setup test needs at least two players")
		return false

	var available_p1: Array = game._available_starting_mages(0)

	if available_p1.size() < 2:
		print("FAIL: expected at least two implemented Mages")
		return false

	var first_mage_id: String = str(
		available_p1[0].get(
			"id",
			""
		)
	)

	var saved_p1_mage_id: String = game.players[0].mage_id
	var saved_p2_mage_id: String = game.players[1].mage_id

	game.players[0].mage_id = first_mage_id
	game.players[1].mage_id = ""

	var available_p2: Array = game._available_starting_mages(1)

	for mage_value in available_p2:
		var mage: Dictionary = mage_value

		if str(mage.get("id", "")) == first_mage_id:
			print("FAIL: already selected Mage remained available")
			game.players[0].mage_id = saved_p1_mage_id
			game.players[1].mage_id = saved_p2_mage_id
			return false

	game.players[0].mage_id = saved_p1_mage_id
	game.players[1].mage_id = saved_p2_mage_id

	if not game.get_beta_supported_input_types().has(
		"starting_mage_choice"
	):
		print("FAIL: beta input router missing starting_mage_choice")
		return false

	print("PASS: setup selects all Mages before School/Grimoire passes and enforces unique Mages")
	return true


static func _test_quest_decks_v24(
	game
) -> bool:
	var expected_counts: Dictionary = {
		1: 15,
		2: 21,
		3: 13
	}

	for moon in expected_counts:
		var deck: Array = (
			game.quest_database.create_deck_for_moon(
				moon
			)
		)

		if deck.size() != int(
			expected_counts[moon]
		):
			print(
				"FAIL: Moon ",
				moon,
				" Quest count ",
				deck.size(),
				" expected ",
				expected_counts[moon]
			)
			return false

	var summoner_card: QuestCardState = (
		game.quest_database.get_quest(
			"summoner"
		)
	)

	if summoner_card == null \
	or summoner_card.task.get(
		"elements",
		[]
	) != ["profane"]:
		print("FAIL: Third Moon Summoner task is not Profane/All")
		return false

	var theurge_card: QuestCardState = (
		game.quest_database.get_quest(
			"theurge"
		)
	)

	if theurge_card == null \
	or theurge_card.task.get(
		"elements",
		[]
	) != [
			"sacred",
			"profane"
		]:
		print("FAIL: Theurge task elements are wrong")
		return false

	print("PASS: Quest decks contain 15 / 21 / 13 cards with corrected Third Moon symbol tasks")
	return true


static func _test_second_third_moon_task_matching_v24(
	game,
	player_index: int
) -> bool:
	var player = game.players[
		player_index
	]

	var saved_active: Array = player.active_quests.duplicate()
	var saved_completed: Array = player.completed_quests.duplicate()
	var saved_revealed: Array = player.revealed_spells.duplicate()
	var saved_room: String = player.mage.room_id
	var saved_coord: Vector2i = player.mage.room_coord
	var saved_cell: bool = player.mage.in_cell

	player.active_quests.clear()
	player.completed_quests.clear()
	player.revealed_spells.clear()

	var cinder_gold: QuestState = _new_active_quest(
		game,
		player_index,
		"cinder_and_gold"
	)

	game.quest_manager.process_event(
		game,
		{
			"type": "room_effect_resolved",
			"player_index": player_index,
			"room_color": "yellow",
			"room_id": "bibliotheca"
		}
	)

	if cinder_gold == null \
	or cinder_gold.progress != 1:
		print("FAIL: Second Moon multi-color Room Quest did not progress")
		return false

	var enigmatic: QuestState = _new_active_quest(
		game,
		player_index,
		"enigmatic_sun"
	)

	game.quest_manager.process_event(
		game,
		{
			"type": "effect_resolved",
			"player_index": player_index,
			"source_kind": "spell",
			"effect_type": "convert_instability",
			"instability_converted": 1,
			"effect_room_color": "purple"
		}
	)

	if enigmatic == null \
	or enigmatic.progress != 1:
		print("FAIL: instability conversion/color Quest did not progress")
		return false

	var power_catalyst: QuestState = _new_active_quest(
		game,
		player_index,
		"power_catalyst"
	)

	game.quest_manager.process_event(
		game,
		{
			"type": "damage_inflicted",
			"player_index": player_index,
			"target_model_type": "mage",
			"amount": 1
		}
	)

	if power_catalyst == null \
	or power_catalyst.progress != 1:
		print("FAIL: Power Catalyst did not progress on actual Damage")
		return false

	player.active_quests.clear()
	player.active_quests.append_array(saved_active)
	player.completed_quests.clear()
	player.completed_quests.append_array(saved_completed)
	player.revealed_spells.clear()
	player.revealed_spells.append_array(saved_revealed)
	player.mage.room_id = saved_room
	player.mage.room_coord = saved_coord
	player.mage.in_cell = saved_cell

	print("PASS: Moon II/III QuestManager handles Room colors, Instability conversion and actual Damage triggers")
	return true


static func _test_forgotten_beta_v24(
	game,
	player_index: int
) -> bool:
	if game.active_school_ids.has("forgotten"):
		print("FAIL: Forgotten incorrectly exposed as an Active School")
		return false

	if game.school_libraries.has("forgotten"):
		print("FAIL: Forgotten incorrectly created as a Study Library")
		return false

	var required_ids: Array[String] = [
		"arcane_barrage",
		"killer_fog",
		"supreme_fireball"
	]

	for spell_id in required_ids:
		var spell: SpellCardState = (
			game.spell_database.get_spell(
				spell_id
			)
		)

		if spell == null or not spell.forgotten:
			print(
				"FAIL: missing beta Forgotten ",
				spell_id
			)
			return false

	var arcane: SpellCardState = (
		game.spell_database.get_spell(
			"arcane_barrage"
		)
	)

	if str(
		arcane.light_side.get(
			"element",
			""
		)
	) != "earth" \
	or str(
		arcane.dark_side.get(
			"element",
			""
		)
	) != "earth":
		print("FAIL: Arcane Barrage element should be Earth")
		return false

	var player = game.players[
		player_index
	]

	var saved_hand: Array[SpellCardState] = player.hand.duplicate()
	var saved_memories: Array[SpellCardState] = player.memories.duplicate()
	var saved_removed: Array[SpellCardState] = (
		game.forgotten_removed_from_game.duplicate()
	)

	player.hand.clear()
	player.memories.clear()

	player.hand.append(
		arcane
	)

	if not game.discard_player_spell(
		player_index,
		arcane
	):
		print("FAIL: could not discard beta Forgotten")
		return false

	if player.memories.has(arcane):
		print("FAIL: Forgotten Spell incorrectly entered Memories")
		return false

	if not game.forgotten_removed_from_game.has(
		arcane
	):
		print("FAIL: Forgotten Spell was not removed from game")
		return false

	player.hand.clear()
	player.hand.append_array(saved_hand)
	player.memories.clear()
	player.memories.append_array(saved_memories)
	game.forgotten_removed_from_game.clear()
	game.forgotten_removed_from_game.append_array(
		saved_removed
	)

	print("PASS: beta Forgotten deck uses three implemented cards and Forgotten cards leave the game instead of Memories")
	return true
