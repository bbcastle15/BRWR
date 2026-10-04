class_name QuestManager
extends RefCounted


# =========================================================
# QUEST DRAW / DISCARD
# =========================================================

func draw_phase_quest(game, player_index: int) -> QuestState:
	if not _valid_player(game, player_index):
		return null
	# Visibility does not affect whether a Quest occupies the active slot.
	if not game.players[player_index].active_quests.is_empty():
		return null
	return draw_quest(game, player_index)

func _refresh_quest_boards(game) -> void:
	for board in game.player_boards:
		if is_instance_valid(board):
			board.refresh_quests()

func draw_quest(
	game,
	player_index: int,
	from_moon: int = 0
) -> QuestState:

	if not _valid_player(game, player_index):
		return null

	var moon: int = from_moon if from_moon > 0 else game.current_moon
	var deck: Array = game.quest_decks.get(
		moon,
		[]
	)

	if deck.is_empty():
		print(
			"QuestManager: Moon ",
			moon,
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

	_refresh_quest_boards(game)
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



func process_game_event(
	game,
	event: GameEvent
) -> void:
	if game == null or event == null:
		return

	var base_event: Dictionary = {
		"type": event.event_type,
		"source_kind": "game_event",
		"source_model_type": event.source_model_type,
		"source_player_index": event.source_player_index,
		"target_model_type": event.target_model_type,
		"target_player_index": event.target_player_index,
		"target_evocation": event.target_evocation,
		"source_room_id": event.source_room_id,
		"target_room_id": event.target_room_id,
		"amount": event.amount,
		"action_type": event.action_type
	}

	if event.event_type == "damage_inflicted":
		if event.source_player_index < 0:
			return

		base_event["player_index"] = event.source_player_index
		process_event(
			game,
			base_event
		)
		return

	if event.event_type == "mage_defeated":
		# Master of Death can complete for a Mage who did not inflict the final
		# point of Damage, so every player gets to evaluate the defeated Mage.
		for player_index in range(game.players.size()):
			var candidate: Dictionary = base_event.duplicate(true)
			candidate["player_index"] = player_index
			process_event(
				game,
				candidate
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

	if required_trigger == "damage_or_heal_evocation":
		var is_damage: bool = (
			event_type == "damage_inflicted"
			and str(
				event.get(
					"target_model_type",
					""
				)
			) == "evocation"
			and int(event.get("amount", 0)) > 0
		)

		var is_heal: bool = (
			event_type == "effect_resolved"
			and str(
				event.get(
					"effect_target_model_type",
					""
				)
			) == "evocation"
			and int(
				event.get(
					"damage_healed",
					0
				)
			) > 0
		)

		if not is_damage and not is_heal:
			return false

	elif required_trigger == "" \
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
	# -----------------------------------------------------

	if task.has("spell_type"):
		if str(event.get("spell_type", "")) \
		!= str(task.get("spell_type", "")):
			return false
	if task.has("spell_types") and not str(event.get("spell_type", "")) in task["spell_types"]:
		return false


	# -----------------------------------------------------
	# SPELL ELEMENT(S)
	# All-Elements can satisfy any requested Element.
	# -----------------------------------------------------

	if task.has("element") or task.has("elements"):
		var required_elements: Array[String] = []

		if task.has("elements"):
			for value in task.get("elements", []):
				required_elements.append(str(value))
		else:
			required_elements.append(
				str(task.get("element", ""))
			)

		var actual_element: String = str(
			event.get(
				"spell_element",
				event.get("element", "")
			)
		)

		if actual_element != "all" \
		and not actual_element in required_elements:
			return false


	# -----------------------------------------------------
	# ROOM COLOR / ROOM ID
	# -----------------------------------------------------

	if task.has("room_color"):
		if str(event.get("room_color", "")) \
		!= str(task.get("room_color", "")):
			return false

	if task.has("room_colors"):
		var allowed_colors: Array[String] = []

		for value in task.get("room_colors", []):
			allowed_colors.append(str(value))

		if not str(
			event.get(
				"room_color",
				""
			)
		) in allowed_colors:
			return false

	if task.has("room_id"):
		if str(event.get("room_id", "")) \
		!= str(task.get("room_id", "")):
			return false

	if task.has("in_room_id"):
		var caster_room_id: String = str(
			event.get(
				"caster_room_id",
				event.get("source_room_id", "")
			)
		)

		if caster_room_id != str(
			task.get(
				"in_room_id",
				""
			)
		):
			return false


	# -----------------------------------------------------
	# KEYWORD
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
	# GENERIC MINIMUM
	# -----------------------------------------------------

	if task.has("minimum") \
	and event_type == "damage_inflicted":
		if int(event.get("amount", 0)) < int(
			task.get(
				"minimum",
				1
			)
		):
			return false


	# -----------------------------------------------------
	# EXTRA CONDITIONS
	# -----------------------------------------------------

	if task.has("condition"):
		var condition: String = str(
			task.get(
				"condition",
				""
			)
		)

		match condition:
			"places_instability":
				var minimum: int = int(
					task.get(
						"minimum",
						1
					)
				)

				if int(
					event.get(
						"instability_placed",
						0
					)
				) < minimum:
					return false

			"places_or_converts_instability_in_room_color":
				var total_changed: int = (
					int(
						event.get(
							"instability_placed",
							0
						)
					)
					+ int(
						event.get(
							"instability_converted",
							0
						)
					)
				)

				if total_changed < int(
					task.get(
						"minimum",
						1
					)
				):
					return false

				if str(
					event.get(
						"effect_room_color",
						""
					)
				) != str(
					task.get(
						"room_color",
						""
					)
				):
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
				if not _check_revealed_spell_symbols_legacy(
					game,
					player_index,
					task
				):
					return false

			"defeated_mage_has_your_damage":
				var target_index: int = int(
					event.get(
						"target_player_index",
						-1
					)
				)

				if target_index < 0 \
				or target_index >= game.players.size():
					return false

				if not player_index in game.players[
					target_index
				].mage.damage_cubes:
					return false

			"damage_or_heal_evocation":
				# Kept for compatibility with alternate JSON encodings.
				pass

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
	_refresh_quest_boards(game)

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
	_refresh_quest_boards(game)

	print(
		"Player ",
		player_index + 1,
		" completed Quest: ",
		quest.get_name()
	)
	var event := GameEvent.new("quest_completed")
	event.source_model_type = "mage"
	event.source_player_index = player_index
	event.source_room_id = player.mage.room_id
	event.data = {"quest_id": quest.get_id()}
	game.queue_resolution({"type": "game_event", "event": event})



func complete_active_quest(
	game,
	player_index: int,
	quest: QuestState
) -> bool:
	if not _valid_player(game, player_index):
		return false

	if quest == null \
	or not quest in game.players[
		player_index
	].active_quests:
		return false

	_complete_quest(
		game,
		player_index,
		quest
	)

	return true



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

	for effect in game.get_active_event_effects("on_quest_resolved_mage_and_black_rose_gain_power"):
		game.add_player_power(player_index, int(effect.get("mage_amount", 2)))
		game.add_black_rose_power(int(effect.get("black_rose_amount", 1)))

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
		player.completed_quests.filter(func(quest): return quest.is_completed()).size() - player.max_active_quests
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
	# Count the active header's Element once, matching Enhancement checks.
	# Symbols in an Enhancement condition do not give the card those Elements.
	var main_element: String = str(side.get("element", ""))
	return 1 if _element_matches(main_element, required_elements) else 0


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
