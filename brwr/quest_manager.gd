class_name QuestManager
extends RefCounted


# =========================================================
# QUEST DRAW / DISCARD
# =========================================================

func draw_quest(
	game,
	player_index: int
) -> QuestState:

	if not _valid_player(game, player_index):
		return null

	var deck: Array = game.quest_decks.get(
		game.current_moon,
		[]
	)

	if deck.is_empty():
		print(
			"QuestManager: Moon ",
			game.current_moon,
			" Quest deck is empty"
		)
		return null

	var card: QuestCardState = deck.pop_back()

	var quest := QuestState.new(
		card,
		player_index
	)

	game.players[player_index].active_quests.append(
		quest
	)

	print(
		"Player ",
		player_index + 1,
		" drew Quest: ",
		card.card_name
	)

	return quest


func discard_active_quest(
	game,
	player_index: int,
	quest: QuestState
) -> bool:

	if not _valid_player(game, player_index):
		return false

	var player = game.players[player_index]

	if not quest in player.active_quests:
		return false

	player.active_quests.erase(quest)
	game.quest_discard.append(quest.card)

	print(
		"Player ",
		player_index + 1,
		" discarded Active Quest: ",
		quest.get_name()
	)

	return true


func discard_completed_quest(
	game,
	player_index: int,
	quest: QuestState
) -> bool:

	if not _valid_player(game, player_index):
		return false

	var player = game.players[player_index]

	if not quest in player.completed_quests:
		return false

	player.completed_quests.erase(quest)
	game.quest_discard.append(quest.card)

	print(
		"Player ",
		player_index + 1,
		" discarded Completed Quest: ",
		quest.get_name()
	)

	return true


# =========================================================
# TASK EVENTS
# =========================================================

func process_event(
	game,
	event: Dictionary
) -> void:

	var player_index: int = int(
		event.get(
			"player_index",
			-1
		)
	)

	if not _valid_player(
		game,
		player_index
	):
		return

	var player = game.players[player_index]

	# Snapshot because a Quest can move from Active
	# to Completed while processing the event.
	var quests: Array = (
		player.active_quests.duplicate()
	)

	for quest in quests:

		if quest == null:
			continue

		if not quest.is_active():
			continue

		var task: Dictionary = quest.get_task()

		var trigger: String = str(
			task.get(
				"trigger",
				""
			)
		)

		# State-based Quests are checked separately.
		if trigger == "game_state_check":
			continue

		if not _task_matches(
			task,
			event
		):
			continue

		_progress_quest(
			game,
			player_index,
			quest
		)

	# Some Quests can become valid as a consequence
	# of the event that has just resolved.
	check_state_quests(
		game,
		player_index
	)

# =========================================================
# TASK MATCHING
# =========================================================

func _task_matches(
	task: Dictionary,
	event: Dictionary
) -> bool:

	if task.is_empty():
		return false

	var required_trigger: String = str(
		task.get(
			"trigger",
			""
		)
	)

	var event_type: String = str(
		event.get(
			"type",
			""
		)
	)

	if required_trigger == "":
		return false

	if event_type != required_trigger:
		return false


	# -----------------------------------------------------
	# SPELL TYPE
	#
	# Example:
	# Contingent Mage
	# -----------------------------------------------------

	if task.has("spell_type"):

		var required_spell_type: String = str(
			task.get(
				"spell_type",
				""
			)
		)

		var actual_spell_type: String = str(
			event.get(
				"spell_type",
				""
			)
		)

		if actual_spell_type != required_spell_type:
			return false


	# -----------------------------------------------------
	# ELEMENT
	#
	# Example:
	# Shattered Illusion
	# -----------------------------------------------------

	if task.has("element"):

		var required_element: String = str(
			task.get(
				"element",
				""
			)
		)

		var actual_element: String = str(
			event.get(
				"element",
				""
			)
		)

		if actual_element != required_element:
			return false


	return true


# =========================================================
# QUEST PROGRESSION
# =========================================================

func _progress_quest(
	game,
	player_index: int,
	quest: QuestState
) -> void:

	if quest == null:
		return

	var task: Dictionary = quest.get_task()


	# -----------------------------------------------------
	# QUEST WITHOUT CUBE PROGRESSION
	# -----------------------------------------------------

	if quest.get_cube_slots() <= 0:

		quest.reveal()

		_complete_quest(
			game,
			player_index,
			quest
		)

		return


	# -----------------------------------------------------
	# QUEST WITH CUBE PROGRESSION
	# -----------------------------------------------------

	if not quest.revealed:
		quest.reveal()

		print(
			"Player ",
			player_index + 1,
			" revealed Quest: ",
			quest.get_name()
		)

	var amount: int = int(
		task.get(
			"progress",
			1
		)
	)

	var completed_now: bool = quest.add_progress(
		amount
	)

	print(
		"Quest progress: ",
		quest.get_name(),
		" | ",
		quest.progress,
		"/",
		quest.get_cube_slots()
	)

	if completed_now:
		_complete_quest(
			game,
			player_index,
			quest
		)


# =========================================================
# COMPLETE QUEST
# =========================================================

func _complete_quest(
	game,
	player_index: int,
	quest: QuestState
) -> void:

	if not _valid_player(
		game,
		player_index
	):
		return

	var player = game.players[player_index]

	if quest in player.active_quests:
		player.active_quests.erase(
			quest
		)

	if not quest.completed:
		quest.complete()

	if not quest in player.completed_quests:
		player.completed_quests.append(
			quest
		)

	print(
		"Player ",
		player_index + 1,
		" completed Quest: ",
		quest.get_name()
	)


# =========================================================
# SOLVE QUEST
# =========================================================

func solve_quest(
	game,
	player_index: int,
	quest: QuestState,
	context: Dictionary = {}
) -> bool:

	if not _valid_player(
		game,
		player_index
	):
		return false

	var player = game.players[player_index]

	if not quest in player.completed_quests:
		return false

	if not quest.is_completed():
		return false

	var quest_context: Dictionary = (
		context.duplicate(true)
	)

	quest_context["game"] = game
	quest_context["caster_id"] = player_index
	quest_context["caster_room_id"] = (
		player.mage.room_id
	)


	var effects: Array = quest.get_effects()

	if not effects.is_empty():

		var success: bool = (
			game.effect_resolver.resolve_effects(
				effects,
				quest_context
			)
		)

		if not success:
			print(
				"QuestManager: failed to resolve Quest: ",
				quest.get_name()
			)
			return false


	quest.solve()


	var reward: int = quest.get_power_reward()

	if reward > 0:
		game.add_player_power(
			player_index,
			reward
		)


	print(
		"Player ",
		player_index + 1,
		" solved Quest: ",
		quest.get_name(),
		" | Reward: ",
		reward,
		" Power"
	)

	return true


# =========================================================
# LIMIT HELPERS
# =========================================================

func get_active_excess(
	game,
	player_index: int
) -> int:

	if not _valid_player(
		game,
		player_index
	):
		return 0

	var player = game.players[player_index]

	return max(
		0,
		player.active_quests.size()
		- player.max_active_quests
	)


func get_completed_excess(
	game,
	player_index: int
) -> int:

	if not _valid_player(
		game,
		player_index
	):
		return 0

	var player = game.players[player_index]

	return max(
		0,
		player.completed_quests.size()
		- player.max_active_quests
	)


# =========================================================
# HELPERS
# =========================================================

func _valid_player(
	game,
	player_index: int
) -> bool:

	if game == null:
		return false

	return (
		player_index >= 0
		and player_index < game.players.size()
	)
func check_state_quests(
	game,
	player_index: int
) -> void:

	if not _valid_player(
		game,
		player_index
	):
		return

	var player = game.players[player_index]

	var quests: Array = (
		player.active_quests.duplicate()
	)

	for quest in quests:

		if quest == null:
			continue

		if not quest.is_active():
			continue

		var task: Dictionary = quest.get_task()

		if str(
			task.get(
				"trigger",
				""
			)
		) != "game_state_check":
			continue

		if not _state_task_matches(
			game,
			player_index,
			task
		):
			continue

		if not quest.revealed:
			quest.reveal()

			print(
				"Player ",
				player_index + 1,
				" revealed Quest: ",
				quest.get_name()
			)

		_complete_quest(
			game,
			player_index,
			quest
		)
func _state_task_matches(
	game,
	player_index: int,
	task: Dictionary
) -> bool:

	if not _valid_player(
		game,
		player_index
	):
		return false

	var condition: String = str(
		task.get(
			"condition",
			""
		)
	)

	match condition:

		"revealed_spell_symbols":
			return _check_revealed_spell_symbols(
				game,
				player_index,
				task
			)

		_:
			print(
				"QuestManager: unknown state condition: ",
				condition
			)
			return false
func _check_revealed_spell_symbols(
	game,
	player_index: int,
	task: Dictionary
) -> bool:

	var player = game.players[player_index]

	var required_symbol: String = str(
		task.get(
			"symbol",
			""
		)
	)

	var required_amount: int = int(
		task.get(
			"required",
			1
		)
	)

	if required_symbol == "":
		return false

	var total: int = 0

	for revealed in player.revealed_spells:

		if revealed == null:
			continue

		var spell = revealed.spell

		if spell == null:
			continue

		var side: Dictionary

		if revealed.use_dark_side:
			side = spell.dark_side
		else:
			side = spell.light_side

		var symbols: Array = side.get(
			"symbols",
			[]
		)

		for symbol in symbols:

			if str(symbol) == required_symbol:
				total += 1

				if total >= required_amount:
					return true

	return false
