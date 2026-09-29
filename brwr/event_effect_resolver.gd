class_name EventEffectResolver
extends RefCounted


func resolve_event(
	event: EventCardState,
	context: Dictionary
) -> bool:

	if event == null:
		return false


	var effects: Array = event.effects


	for effect in effects:

		if not resolve_effect(
			effect,
			context
		):

			return false


	return true


func resolve_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var effect_type: String = str(
		effect.get(
			"type",
			""
		)
	)


	match effect_type:
		"on_activate_room_color_black_rose_gain_power":
			# Consumed by Game when a matching Room activation finishes.
			return true

		"black_rose_instability":
			return _resolve_black_rose_instability(
				effect,
				context
			)


		"black_rose_instability_room_colors":
			return _resolve_black_rose_instability_room_colors(
				effect,
				context
			)


		"black_rose_damage_all_evocations":
			return _resolve_black_rose_damage_all_evocations(
				effect,
				context
			)


		"each_mage_lose_power":
			return _resolve_each_mage_lose_power(
				effect,
				context
			)


		"each_mage_may_draw_library":
			return _resolve_each_mage_may_draw_library(
				effect,
				context
			)


		"each_mage_may_place_model":
			return _resolve_each_mage_may_place_model(
				effect,
				context
			)


		"each_mage_place_from_cell":
			return _resolve_each_mage_place_from_cell(
				effect,
				context
			)


		"each_mage_may_summon_evocation":
			return _resolve_each_mage_may_summon_evocation(
				effect,
				context
			)


		_:
			print(
				"Unknown Event effect: ",
				effect_type
			)

			return false


# =========================================================
# BLACK ROSE INSTABILITY — SPECIFIC ROOM
# =========================================================

func _resolve_black_rose_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	var room_id: String = str(
		effect.get(
			"room_id",
			""
		)
	)


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	if room_id.is_empty():
		return false


	game.place_instability(
		-1,
		room_id,
		amount
	)


	return true


# =========================================================
# BLACK ROSE INSTABILITY — ROOM COLORS
# =========================================================

func _resolve_black_rose_instability_room_colors(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	var colors: Array = effect.get(
		"colors",
		[]
	)


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	for child in game.get_children():

		if not child.has_meta(
			"room_id"
		):
			continue


		if child.flipped:
			continue


		var room_color: String = str(
			child.room_data.get(
				"color",
				""
			)
		)


		if not colors.has(
			room_color
		):
			continue


		var room_id: String = str(
			child.get_meta(
				"room_id"
			)
		)


		game.place_instability(
			-1,
			room_id,
			amount
		)


	return true


# =========================================================
# BLACK ROSE DAMAGE ALL EVOCATIONS
# =========================================================

func _resolve_black_rose_damage_all_evocations(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	# Copia preventiva perché alcune Evocation possono
	# essere sconfitte/rimosse durante la risoluzione.

	var targets: Array = []


	for player in game.players:

		for evocation in player.evocations:

			if evocation == null:
				continue

			if evocation.is_defeated():
				continue

			targets.append(
				evocation
			)


	for evocation in targets:

		if evocation.is_defeated():
			continue


		game.deal_damage_to_evocation(
			-1,
			evocation,
			amount
		)


	return true


# =========================================================
# EACH MAGE LOSES POWER
# =========================================================

func _resolve_each_mage_lose_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	for player_index in _play_order(
		context
	):

		game.add_player_power(
			player_index,
			-amount
		)


	return true


# =========================================================
# EACH MAGE MAY DRAW FROM LIBRARY
#
# Context:
#
# "event_library_choices": {
#     0: "agony",
#     1: "",
#     2: "alchemy"
# }
#
# Stringa vuota = il giocatore rifiuta.
# =========================================================

func _resolve_each_mage_may_draw_library(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	var choices: Dictionary = context.get(
		"event_library_choices",
		{}
	)


	for player_index in _play_order(
		context
	):

		if not choices.has(
			player_index
		):
			continue


		var school_id: String = str(
			choices[player_index]
		)


		# "may" -> scelta di non pescare

		if school_id.is_empty():
			continue


		if not game.is_school_active(
			school_id
		):

			return false


		for i in range(amount):

			var spell = (
				game.draw_from_school_library(
					school_id
				)
			)


			if spell == null:
				return false


			game.players[
				player_index
			].hand.append(
				spell
			)


	return true


# =========================================================
# EACH MAGE MAY PLACE MODEL
#
# Usato da Dislocation.
#
# Context:
#
# "event_mage_destinations": {
#     0: "arena",
#     1: "",
#     2: "crypt"
# }
#
# "" = il giocatore non usa l'effetto.
# =========================================================

func _resolve_each_mage_may_place_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var max_distance: int = int(
		effect.get(
			"range",
			0
		)
	)


	var destinations: Dictionary = context.get(
		"event_mage_destinations",
		{}
	)


	for player_index in _play_order(
		context
	):

		if not destinations.has(
			player_index
		):
			continue


		var destination_room_id: String = str(
			destinations[
				player_index
			]
		)


		if destination_room_id.is_empty():
			continue


		if not game.move_mage_to_room_id(
			player_index,
			destination_room_id,
			max_distance
		):

			return false


	return true


# =========================================================
# EACH MAGE PLACES FROM OWN CELL
#
# A Hard Lesson.
#
# Context usa ancora:
#
# "event_mage_destinations"
# =========================================================

func _resolve_each_mage_place_from_cell(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	var max_distance: int = int(
		effect.get(
			"range",
			1
		)
	)


	var destinations: Dictionary = context.get(
		"event_mage_destinations",
		{}
	)


	for player_index in _play_order(
		context
	):

		if not destinations.has(
			player_index
		):

			print(
				"A Hard Lesson: destination missing for Player ",
				player_index + 1
			)

			return false


		var destination_room_id: String = str(
			destinations[
				player_index
			]
		)


		if destination_room_id.is_empty():
			return false


		# La carta specifica placement dalla propria Cell.
		# Questo NON deve attivare Hidden Resources:
		# non stiamo piazzando il Mage NELLA Cell.
		game.players[
			player_index
		].mage.in_cell = true


		if not game.move_mage_to_room_id(
			player_index,
			destination_room_id,
			max_distance
		):

			return false


	return true


# =========================================================
# EACH MAGE MAY SUMMON EVOCATION
#
# Undead Army.
#
# Context:
#
# "event_summon_choices": {
#     0: "arena",
#     1: "",
#     2: "crypt"
# }
#
# "" = non evoca.
# =========================================================

func _resolve_each_mage_may_summon_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var evocation_id: String = str(
		effect.get(
			"evocation_id",
			""
		)
	)


	var choices: Dictionary = context.get(
		"event_summon_choices",
		{}
	)


	for player_index in _play_order(
		context
	):

		if not choices.has(
			player_index
		):
			continue


		var room_id: String = str(
			choices[
				player_index
			]
		)


		if room_id.is_empty():
			continue


		var mage = game.players[
			player_index
		].mage


		if mage.in_cell:
			continue


		# Undead Army ha Range 0:
		# il Cadaver deve essere evocato nella Room del Mage.

		if room_id != mage.room_id:
			return false


		var evocation = game.summon_evocation(
			player_index,
			evocation_id,
			room_id
		)


		if evocation == null:
			return false


	return true


# =========================================================
# HELPERS
# =========================================================

func _game(
	context: Dictionary
):
	return context.get(
		"game"
	)

func _play_order(
	context: Dictionary
) -> Array[int]:

	var result: Array[int] = []

	var game = _game(
		context
	)


	if game == null:
		return result


	if context.has(
		"play_order"
	):

		for player_index in context[
			"play_order"
		]:

			result.append(
				int(player_index)
			)


		return result


	return game.get_play_order()
