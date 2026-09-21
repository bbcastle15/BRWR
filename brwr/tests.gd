extends RefCounted


static func run(game) -> void:

	print("")
	print("========================================")
	print("QUEST INTEGRATION TEST")
	print("========================================")


	var player_index: int = 0
	var player = game.players[player_index]


	player.active_quests.clear()
	player.completed_quests.clear()


	var card = game.quest_database.get_quest(
		"shattered_illusion"
	)

	if card == null:
		print("FAIL: Quest not found")
		return


	var quest := QuestState.new(
		card,
		player_index
	)

	player.active_quests.append(
		quest
	)


	# =====================================================
	# Simulate a REAL effect_sequence frame.
	#
	# We use gain_power because it is a normal implemented
	# Spell Effect. The Quest cares about the Spell element,
	# not about this Effect type.
	# =====================================================

	var context: Dictionary = {
		"game": game,
		"caster_id": player_index,
		"spell_element": "illusion"
	}


	var frame: Dictionary = {
		"type": "effect_sequence",
		"resolver_kind": "spell",
		"effects": [
			{
				"type": "gain_power",
				"amount": 1
			}
		],
		"index": 0,
		"context": context
	}


	game.process_effect_sequence_resolution(
		frame
	)


	if quest.progress != 1:
		print(
			"FAIL: expected Quest progress 1, got ",
			quest.progress
		)
		return


	if not quest.revealed:
		print(
			"FAIL: Quest was not revealed"
		)
		return


	print(
		"PASS: real Effect resolution -> Quest 1/2"
	)


	# Second real Effect.

	frame = {
		"type": "effect_sequence",
		"resolver_kind": "spell",
		"effects": [
			{
				"type": "gain_power",
				"amount": 1
			}
		],
		"index": 0,
		"context": context
	}


	game.process_effect_sequence_resolution(
		frame
	)


	if quest.progress != 2:
		print(
			"FAIL: expected Quest progress 2, got ",
			quest.progress
		)
		return


	if not quest.completed:
		print(
			"FAIL: Quest was not completed"
		)
		return


	if quest in player.active_quests:
		print(
			"FAIL: Quest still Active"
		)
		return


	if not quest in player.completed_quests:
		print(
			"FAIL: Quest not in Completed"
		)
		return


	print(
		"PASS: second real Effect -> Quest Completed"
	)


	print("")
	print("========================================")
	print("QUEST INTEGRATION: ALL TESTS PASSED")
	print("========================================")
