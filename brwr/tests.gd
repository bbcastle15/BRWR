extends RefCounted


static func run(game) -> void:
	print("")
	print("========================================")
	print("QUEST SYSTEM V6 TEST")
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

	print("")
	print("========================================")
	print("QUEST SYSTEM V6: ALL TESTS PASSED")
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
