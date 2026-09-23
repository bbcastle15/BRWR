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

	# Some Quest cards explicitly say "Reveal this card."
	if bool(card.task.get("reveal_immediately", false)):
		quest.reveal()

	print(
		"Player ",
		player_index + 1,
		" drew Quest: ",
		card.card_name,
		" | revealed=",
		quest.revealed
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
		event.get("player_index", -1)
	)

	if not _valid_player(game, player_index):
		return

	var player = game.players[player_index]

	# Snapshot because a Quest can move from Active to Completed
	# while the same event is being processed.
	var quests: Array = player.active_quests.duplicate()

	for quest in quests:

		if quest == null:
			continue

		if not quest.is_active():
			continue

		var task: Dictionary = quest.get_task()
		var trigger: String = str(task.get("trigger", ""))

		# Kept for future/backward-compatible state based Quests.
		if trigger == "game_state_check":
			continue

		if not _task_matches(
			game,
			player_index,
			task,
			event
		):
			continue

		_progress_quest(
			game,
			player_index,
			quest
		)

	# State-based Quests are evaluated after the event as well.
	check_state_quests(
		game,
		player_index
	)


# =========================================================
# TASK MATCHING
# =========================================================

func _task_matches(
	game,
	player_index: int,
	task: Dictionary,
	event: Dictionary
) -> bool:

	if task.is_empty():
		return false

	var required_trigger: String = str(
		task.get("trigger", "")
	)
	var event_type: String = str(
		event.get("type", "")
	)

	if required_trigger == "" \
	or event_type != required_trigger:
		return false


	# -----------------------------------------------------
	# SOURCE KIND
	# -----------------------------------------------------

	if task.has("source_kind"):
		if str(event.get("source_kind", "")) \
		!= str(task.get("source_kind", "")):
			return false


	# -----------------------------------------------------
	# SPELL TYPE
	# Combat / Contingency / Trap / Protection.
	# -----------------------------------------------------

	if task.has("spell_type"):
		if str(event.get("spell_type", "")) \
		!= str(task.get("spell_type", "")):
			return false


	# -----------------------------------------------------
	# ROOM COLOR
	# -----------------------------------------------------

	if task.has("room_color"):
		if str(event.get("room_color", "")) \
		!= str(task.get("room_color", "")):
			return false


	# -----------------------------------------------------
	# LEGACY SINGLE ELEMENT MATCH
	# -----------------------------------------------------

	if task.has("element"):
		var actual_element: String = str(
			event.get(
				"spell_element",
				event.get("element", "")
			)
		)

		if actual_element != str(task.get("element", "")):
			return false


	# -----------------------------------------------------
	# KEYWORD
	# Example: Summoner Wizard -> Summon keyword.
	# -----------------------------------------------------

	if task.has("keyword"):
		var required_keyword: String = str(
			task.get("keyword", "")
		)
		var keywords: Array = event.get("keywords", [])
		var found_keyword := false

		for keyword in keywords:
			if str(keyword) == required_keyword:
				found_keyword = true
				break

		if not found_keyword:
			return false


	# -----------------------------------------------------
	# EXTRA CONDITION
	# -----------------------------------------------------

	if task.has("condition"):
		var condition: String = str(task.get("condition", ""))

		match condition:
			"places_instability":
				var minimum: int = int(task.get("minimum", 1))
				if int(event.get("instability_placed", 0)) < minimum:
					return false

			"revealed_spell_elements":
				if not _check_revealed_spell_elements(
					game,
					player_index,
					task,
					event
				):
					return false

			"revealed_spell_symbols":
				# Backward compatibility with the old test JSON.
				if not _check_revealed_spell_symbols_legacy(
					game,
					player_index,
					task
				):
					return false

			_:
				print(
					"QuestManager: unknown task condition: ",
					condition
				)
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

	# Quest without cube progression: fulfilling the Task completes it.
	if quest.get_cube_slots() <= 0:
		if not quest.revealed:
			quest.reveal()
			print(
				"Player ", player_index + 1,
				" revealed Quest: ", quest.get_name()
			)

		_complete_quest(
			game,
			player_index,
			quest
		)
		return

	# Quest with cube progression.
	if not quest.revealed:
		quest.reveal()
		print(
			"Player ",
			player_index + 1,
			" revealed Quest: ",
			quest.get_name()
		)

	var amount: int = int(task.get("progress", 1))
	var completed_now: bool = quest.add_progress(amount)

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

	if not _valid_player(game, player_index):
		return

	var player = game.players[player_index]

	if quest in player.active_quests:
		player.active_quests.erase(quest)

	if not quest.completed:
		quest.complete()

	if not quest in player.completed_quests:
		player.completed_quests.append(quest)

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

	if not _valid_player(game, player_index):
		return false

	var player = game.players[player_index]

	if not quest in player.completed_quests:
		return false

	if not quest.is_completed():
		return false

	var quest_context: Dictionary = context.duplicate(true)
	quest_context["game"] = game
	quest_context["caster_id"] = player_index
	quest_context["caster_room_id"] = player.mage.room_id

	# Quest Effects use the same integrated resolution stack as Spell Effects.
	# This is important because Damage, Traps and Protections can interrupt a
	# Quest Effect exactly as described by the rulebook.
	return game.queue_resolution({
		"type": "quest_resolution",
		"step": "start",
		"player_index": player_index,
		"quest": quest,
		"context": quest_context
	})


func finalize_quest_solve(
	game,
	player_index: int,
	quest: QuestState
) -> bool:
	if not _valid_player(game, player_index):
		return false

	var player = game.players[player_index]

	# The frame can resume after nested trigger windows; never award twice.
	if quest.is_solved():
		return true

	if not quest in player.completed_quests or not quest.is_completed():
		return false

	quest.solve()

	var reward: int = quest.get_power_reward()
	if reward > 0:
		game.add_player_power(player_index, reward)

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


func emit_quest_solved_event(
	game,
	player_index: int,
	quest: QuestState
) -> bool:
	if not _valid_player(game, player_index):
		return false

	if quest == null or not quest.is_solved():
		return false

	var event := GameEvent.new("quest_solved")
	event.source_model_type = "mage"
	event.source_player_index = player_index
	event.source_room_id = game.players[player_index].mage.room_id
	event.data = {
		"quest_id": quest.get_id(),
		"quest_name": quest.get_name()
	}

	return game.process_game_event(event)


# =========================================================
# LIMIT HELPERS
# =========================================================

func get_active_excess(
	game,
	player_index: int
) -> int:

	if not _valid_player(game, player_index):
		return 0

	var player = game.players[player_index]
	return max(
		0,
		player.active_quests.size() - player.max_active_quests
	)


func get_completed_excess(
	game,
	player_index: int
) -> int:

	if not _valid_player(game, player_index):
		return 0

	var player = game.players[player_index]
	return max(
		0,
		player.completed_quests.size() - player.max_active_quests
	)


# =========================================================
# STATE-BASED QUESTS / ELEMENT SYMBOLS
# =========================================================

func check_state_quests(
	game,
	player_index: int
) -> void:

	if not _valid_player(game, player_index):
		return

	var player = game.players[player_index]
	var quests: Array = player.active_quests.duplicate()

	for quest in quests:
		if quest == null or not quest.is_active():
			continue

		var task: Dictionary = quest.get_task()

		if str(task.get("trigger", "")) != "game_state_check":
			continue

		if not _state_task_matches(
			game,
			player_index,
			task
		):
			continue

		_progress_quest(
			game,
			player_index,
			quest
		)


func _state_task_matches(
	game,
	player_index: int,
	task: Dictionary
) -> bool:

	var condition: String = str(task.get("condition", ""))

	match condition:
		"revealed_spell_elements":
			return _check_revealed_spell_elements(
				game,
				player_index,
				task,
				{}
			)

		"revealed_spell_symbols":
			return _check_revealed_spell_symbols_legacy(
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


func _check_revealed_spell_elements(
	game,
	player_index: int,
	task: Dictionary,
	event: Dictionary = {}
) -> bool:

	if not _valid_player(game, player_index):
		return false

	var required_elements: Array[String] = []
	for value in task.get("elements", []):
		required_elements.append(str(value))

	if required_elements.is_empty():
		return false

	var required_amount: int = int(task.get("required", 1))
	var total := 0

	for revealed in game.players[player_index].revealed_spells:
		if revealed == null:
			continue

		total += _count_matching_element_symbols(
			revealed.get_active_side(),
			required_elements
		)

		if total >= required_amount:
			return true

	# While a Spell Effect is being resolved, the current Spell is already
	# revealed by the tabletop rules, even though the digital state adds it to
	# revealed_spells only after the whole resolution frame is finished.
	var current_side = event.get("spell_side", {})
	if current_side is Dictionary \
	and not current_side.is_empty():
		total += _count_matching_element_symbols(
			current_side,
			required_elements
		)

	return total >= required_amount


func _count_matching_element_symbols(
	side: Dictionary,
	required_elements: Array[String]
) -> int:

	var total := 0

	# Main Element symbol printed in the Spell header.
	var main_element: String = str(side.get("element", ""))
	if _element_matches(main_element, required_elements):
		total += 1

	# Alchemy-style Enhancement requirements are also printed Element symbols
	# on the Active Side. Current JSONs use requires/elements/element depending
	# on the card, so support all three representations.
	var enhancement = side.get("enhancement", {})
	if enhancement is Dictionary \
	and not enhancement.is_empty():

		var requirements: Array[String] = []

		if enhancement.has("requires"):
			for value in enhancement.get("requires", []):
				requirements.append(str(value))
		elif enhancement.has("elements"):
			for value in enhancement.get("elements", []):
				requirements.append(str(value))
		elif enhancement.has("element"):
			requirements.append(str(enhancement.get("element", "")))

		for element in requirements:
			if _element_matches(element, required_elements):
				total += 1

	return total


func _element_matches(
	element: String,
	required_elements: Array[String]
) -> bool:

	if element == "":
		return false

	# The rulebook defines the All-Elements symbol as a chosen Element when
	# needed, therefore it can satisfy any one requested Element symbol.
	if element == "all":
		return true

	return element in required_elements


func _check_revealed_spell_symbols_legacy(
	game,
	player_index: int,
	task: Dictionary
) -> bool:

	if not _valid_player(game, player_index):
		return false

	var required_symbol: String = str(task.get("symbol", ""))
	var required_amount: int = int(task.get("required", 1))

	if required_symbol == "":
		return false

	var total := 0

	for revealed in game.players[player_index].revealed_spells:
		if revealed == null or revealed.spell == null:
			continue

		var side: Dictionary = revealed.get_active_side()
		for symbol in side.get("symbols", []):
			if str(symbol) == required_symbol:
				total += 1
				if total >= required_amount:
					return true

	return false


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
