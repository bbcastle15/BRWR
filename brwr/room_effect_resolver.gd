class_name RoomEffectResolver
extends RefCounted


# =========================================================
# PUBLIC API
# =========================================================

func resolve_room(
	game,
	player_index: int,
	room,
	context: Dictionary = {}
) -> bool:

	if game == null:
		return false

	if room == null:
		return false

	if player_index < 0 \
	or player_index >= game.players.size():
		return false


	var effects: Array = room.get_effects()

	if effects.is_empty():
		print(
			"Room has no effects: ",
			room.room_name
		)
		return true


	var room_context = context.duplicate()

	room_context["game"] = game
	room_context["player_index"] = player_index
	room_context["caster_id"] = player_index
	room_context["room"] = room
	room_context["room_id"] = room.get_room_id()

	# Default target Room = activated Room.
	if not room_context.has(
		"target_room_id"
	):
		room_context["target_room_id"] = (
			room.get_room_id()
		)


	print("")
	print(
		"ROOM ACTIVATION: ",
		room.room_name,
		" | Player ",
		player_index + 1,
		" | Side: ",
		room.get_current_side_name()
	)


	return resolve_effects(
		effects,
		room_context
	)


func resolve_effects(
	effects: Array,
	context: Dictionary
) -> bool:

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

	var effect_type = str(
		effect.get(
			"type",
			""
		)
	)


	match effect_type:

		# ================================================
		# ALREADY IMPLEMENTABLE PRIMITIVES
		# ================================================

		"gain_power":
			return _resolve_gain_power(
				effect,
				context
			)

		"lose_power":
			return _resolve_lose_power(
				effect,
				context
			)

		"damage":
			return _resolve_damage(
				effect,
				context
			)

		"heal":
			return _resolve_heal(
				effect,
				context
			)

		"place_instability":
			return _resolve_place_instability(
				effect,
				context
			)

		"place_black_rose_instability":
			return _resolve_black_rose_instability(
				effect,
				context
			)

		"summon_evocation":
			return _resolve_summon_evocation(
				effect,
				context
			)

		"activate_last_summoned_evocation":
			return _resolve_activate_last_summoned(
				effect,
				context
			)


		# ================================================
		# ROOM / DECK SYSTEMS
		# ================================================

		"discard_spells":

			return _resolve_discard_spells(
				effect,
				context
			)
		"discard_spell":

			return _resolve_discard_spell(
				effect,
				context
			)
		"draw_forgotten":
			return _resolve_draw_forgotten(effect, context)

		"draw_forgotten_choose":
			return _resolve_draw_forgotten_choose(effect, context)

		"draw_grimoire":

			var game = context.get(
				"game",
				null
			)

			var player_index: int = int(
				context.get(
					"player_index",
					-1
				)
			)

			if game == null:
				return false

			if player_index < 0 \
			or player_index >= game.players.size():
				return false


			var amount: int = int(
				effect.get(
					"amount",
					1
				)
			)


			for i in range(amount):

				var spell = game.draw_player_spell(
					player_index
				)

				if spell == null:
					break


			return true

		"search_grimoire":

			return _resolve_search_grimoire(
				effect,
				context
			)

		"shuffle_grimoire":

			var game = context.get(
				"game",
				null
			)

			var player_index: int = int(
				context.get(
					"player_index",
					-1
				)
			)


			if game == null:
				return false


			return game.shuffle_player_grimoire(
				player_index
			)

		"search_grimoire_or_memories":

			return _resolve_search_grimoire_or_memories(
				effect,
				context
			)
		"search_personal_spell":

			return _resolve_search_personal_spell(
				effect,
				context
			)
		
		"shuffle_memories_into_grimoire":

			var game = context.get(
				"game",
				null
			)

			var player_index: int = int(
				context.get(
					"player_index",
					-1
				)
			)


			if game == null:
				return false


			return game.shuffle_memories_into_grimoire(
				player_index
			)
		"draw_random_memories":

			var game = context.get(
				"game",
				null
			)

			var player_index: int = int(
				context.get(
					"player_index",
					-1
				)
			)

			if game == null:
				return false

			if player_index < 0 \
			or player_index >= game.players.size():
				return false


			var amount: int = int(
				effect.get(
					"amount",
					1
				)
			)


			for i in range(amount):

				var spell = game.draw_random_memory(
					player_index
				)

				if spell == null:
					break


			return true

		"library_draw_choice":

			return _resolve_library_draw_choice(
				effect,
				context
			)
		"draw_library":
			return _resolve_draw_library(
				effect,
				context
			)	
		"draw_quest":
			return _resolve_draw_quest(effect, context)

		"discard_quest":
			return _resolve_discard_quest(effect, context)

		"draw_event":
			return _resolve_draw_event(
				effect,
				context
			)


		# ================================================
		# SPECIAL ROOM MECHANICS
		# ================================================

		"take_crown":
			return _resolve_take_crown(
				context
			)

		"conditional_payment":
			return _resolve_conditional_payment(
				effect,
				context
			)

		"move":
			return _resolve_move(
				effect,
				context
			)

		"copy_room_effect":
			return _resolve_copy_room_effect(
				effect,
				context
			)

		"return_all_mages_to_cells":
			return _resolve_return_all_mages_to_cells(
				context
			)

		"lose_power_other_mages":
			return _resolve_lose_power_other_mages(
				effect,
				context
			)

		"black_rose_gain_power":
			return _resolve_black_rose_gain_power(
				effect,
				context
			)
		"cast_next_ready_spell":

			return _resolve_cast_next_ready_spell(
				effect,
				context	
			)

		"replace_revealed_spell_from_hand":

			return _resolve_replace_revealed_spell_from_hand(
				effect,
				context
			)
		"attack":
			return _resolve_attack(
				effect,
				context
			)


		_:
			print(
				"UNKNOWN ROOM EFFECT TYPE: ",
				effect_type
			)

			return false


# =========================================================
# COMMON HELPERS
# =========================================================

func _game(
	context: Dictionary
):
	return context.get(
		"game"
	)


func _player_index(
	context: Dictionary
) -> int:

	return int(
		context.get(
			"player_index",
			-1
		)
	)


func _room_id(
	context: Dictionary
) -> String:

	return str(
		context.get(
			"room_id",
			""
		)
	)


func _target_room_id(
	context: Dictionary
) -> String:

	return str(
		context.get(
			"target_room_id",
			_room_id(context)
		)
	)


func _valid_player(
	game,
	player_index: int
) -> bool:

	return (
		game != null
		and player_index >= 0
		and player_index < game.players.size()
	)


# =========================================================
# POWER
# =========================================================

func _resolve_gain_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	var player_index = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)


	if amount > 0:
		game.add_player_power(
			player_index,
			amount
		)


	return true


func _resolve_lose_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	var player_index = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)


	if amount > 0:
		game.add_player_power(
			player_index,
			-amount
		)


	return true


func _resolve_black_rose_gain_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)


	if amount > 0:
		game.add_black_rose_power(
			amount
		)


	return true


func _resolve_lose_power_other_mages(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	var activating_player = _player_index(
		context
	)

	if not _valid_player(
		game,
		activating_player
	):
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)


	for player_index in range(
		game.players.size()
	):

		if player_index == activating_player:
			continue

		game.add_player_power(
			player_index,
			-amount
		)


	return true


# =========================================================
# DAMAGE / HEAL
# =========================================================

func _resolve_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true


	var target_type: String = str(
		effect.get(
			"target",
			"mage"
		)
	)


	# =====================================================
	# AREA / ROOM TARGET
	# =====================================================

	if target_type == "room" or target_type == "choose_room":

		var target_room_id: String = _target_room_id(
			context
		)

		if target_room_id == "":
			print("Room damage: target Room missing")
			return false

		# The Mage activating the Room resolves this Effect. Damage every Model
		# in the target Room, while normal own-Effect immunity still applies.
		for target_player_index in range(
			game.players.size()
		):
			var target_mage = game.players[
				target_player_index
			].mage

			if target_mage == null \
			or target_mage.in_cell \
			or target_mage.room_id != target_room_id:
				continue

			if target_player_index == player_index:
				continue

			game.deal_damage(
				player_index,
				target_player_index,
				amount,
				"room"
			)

		for owner_id in range(game.players.size()):
			var snapshot = game.players[
				owner_id
			].evocations.duplicate()

			for evocation in snapshot:
				if evocation == null \
				or evocation.is_defeated() \
				or evocation.room_id != target_room_id:
					continue

				if game.get_evocation_controller_id(
					evocation
				) == player_index:
					continue

				game.deal_damage_to_evocation(
					player_index,
					evocation,
					amount,
					[],
					"room",
					"mage",
					null
				)

		return true


	# =====================================================
	# GENERIC MODEL TARGET
	#
	# Usato ad esempio da Sacrificial Altar:
	#
	# {
	#     "target_model": {
	#         "kind": "mage",
	#         "player_index": 1
	#     }
	# }
	#
	# oppure:
	#
	# {
	#     "target_model": {
	#         "kind": "evocation",
	#         "state": evocation
	#     }
	# }
	# =====================================================

	if target_type == "choose_model":

		if not context.has(
			"target_model"
		):

			print(
				"Room damage: target Model missing"
			)

			return false


		var target_model = context[
			"target_model"
		]


		if not target_model is Dictionary:

			print(
				"Room damage: target_model is not a Dictionary"
			)

			return false


		var damage_done: int = game.deal_damage_to_model(
			player_index,
			target_model,
			amount
		)


		return damage_done >= 0


	# =====================================================
	# MAGE TARGET
	#
	# Mantiene compatibilità con gli effetti esistenti.
	# =====================================================

	var target_player_index: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)


	if not _valid_player(
		game,
		target_player_index
	):

		print(
			"Room damage: target Mage missing"
		)

		return false


	game.deal_damage(
		player_index,
		target_player_index,
		amount,
		"room"
	)


	return true	

func _resolve_heal(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)


	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)


	if amount <= 0:
		return true


	var target_type: String = str(
		context.get(
			"heal_target_type",
			"mage"
		)
	)


	match target_type:

		# =================================================
		# MAGE
		# =================================================

		"mage":

			var target_player_index: int = int(
				context.get(
					"target_player_index",
					player_index
				)
			)


			if not _valid_player(
				game,
				target_player_index
			):

				print(
					"Room heal: invalid target Mage"
				)

				return false


			var mage = game.players[
				target_player_index
			].mage


			var healed: int = 0


			while healed < amount \
			and not mage.damage_cubes.is_empty():

				var owner_id: int = int(
					mage.damage_cubes[
						mage.damage_cubes.size() - 1
					]
				)


				var removed: int = game.heal_damage(
					target_player_index,
					owner_id,
					1
				)


				if removed <= 0:
					break


				healed += removed


			return true


		# =================================================
		# EVOCATION
		# =================================================

		"evocation":

			var evocation = context.get(
				"target_evocation",
				null
			)


			if evocation == null:

				print(
					"Room heal: target Evocation missing"
				)

				return false


			var healed: int = 0


			while healed < amount \
			and not evocation.damage_cubes.is_empty():

				var owner_id: int = int(
					evocation.damage_cubes[
						evocation.damage_cubes.size() - 1
					]
				)


				var removed: int = (
					game.heal_evocation_damage(
						evocation,
						owner_id,
						1
					)
				)


				if removed <= 0:
					break


				healed += removed


			return true


		_:

			print(
				"Room heal: unknown target type: ",
				target_type
			)

			return false

# =========================================================
# INSTABILITY
# =========================================================

func _resolve_place_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	# =====================================================
	# TARGET ROOM
	#
	# Supporta:
	#
	# Singolo effetto:
	# {
	#     "target_room_id": "crypt"
	# }
	#
	# Effetti multipli, come Garden rebuilt:
	# {
	#     "target_room_ids": [
	#         "crypt",
	#         "arena"
	#     ]
	# }
	# =====================================================

	var room_id: String = ""


	if context.has(
		"target_room_ids"
	):

		var target_room_ids = context[
			"target_room_ids"
		]

		if not target_room_ids is Array:

			print(
				"Room Instability: target_room_ids is not an Array"
			)

			return false


		var target_index: int = int(
			context.get(
				"_room_instability_index",
				0
			)
		)


		if target_index >= target_room_ids.size():

			print(
				"Room Instability: not enough target Rooms"
			)

			return false


		room_id = str(
			target_room_ids[
				target_index
			]
		)


		context[
			"_room_instability_index"
		] = target_index + 1


	else:

		room_id = _target_room_id(
			context
		)


	if room_id.is_empty():

		print(
			"Room Instability: target Room missing"
		)

		return false


	# =====================================================
	# TARGET ROOM EXISTS
	# =====================================================

	var target_room = game.get_room_by_id(
		room_id
	)

	if target_room == null:

		print(
			"Room Instability: Room not found: ",
			room_id
		)

		return false


	# =====================================================
	# RANGE
	#
	# "*" = qualsiasi Room
	# numero = distanza massima dal Mage
	# =====================================================

	var range_value = effect.get(
		"range",
		"*"
	)


	if str(range_value) != "*":

		var max_range: int = int(
			range_value
		)

		var mage = game.players[
			player_index
		].mage


		if mage.in_cell and str(context.get("effect_origin_room_id", "")) == "":

			print(
				"Room Instability: Mage is in Cell"
			)

			return false


		var target_coord: Vector2i = (
			game.room_id_to_coord(
				room_id
			)
		)


		var origin_room: String = str(context.get("effect_origin_room_id", mage.room_id))
		var distance: int = game.get_hex_distance(
			game.room_id_to_coord(origin_room),
			target_coord
		)


		if distance > max_range:

			print(
				"Room Instability: target Room out of range | ",
				distance,
				" > ",
				max_range
			)

			return false


	# =====================================================
	# AMOUNT
	# =====================================================

	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	if amount <= 0:
		return true


	# =====================================================
	# PLACE INSTABILITY
	# =====================================================

	game.place_player_instability(
		player_index,
		room_id,
		amount
	)


	return true

func _resolve_black_rose_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var room_id = _target_room_id(
		context
	)

	if room_id == "":
		print(
			"Black Rose Instability: target Room missing"
		)

		return false


	var amount = int(
		effect.get(
			"amount",
			1
		)
	)


	game.place_black_rose_instability(
		room_id,
		amount
	)


	return true


# =========================================================
# EVOCATIONS
# =========================================================

func _resolve_summon_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	var player_index = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var evocation_id = str(
		effect.get(
			"evocation_id",
			""
		)
	)


	var room_id = _room_id(
		context
	)


	if evocation_id == "" \
	or room_id == "":
		return false


	var summoned = game.summon_evocation(
		player_index,
		evocation_id,
		room_id
	)


	if summoned == null:
		return false


	context[
		"last_summoned_evocation"
	] = summoned


	return true


func _resolve_activate_last_summoned(
	_effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	if game == null:
		return false


	var player_index: int = _player_index(
		context
	)


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var evocation = context.get(
		"last_summoned_evocation"
	)


	if evocation == null:
		return false


	return game.activate_evocation(
		evocation,
		player_index,
		context
	)

# =========================================================
# CONDITIONAL PAYMENT
# =========================================================

func _resolve_conditional_payment(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)

	var player_index = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var cost: Dictionary = effect.get(
		"cost",
		{}
	)


	var cost_type = str(
		cost.get(
			"type",
			""
		)
	)


	var amount = int(
		cost.get(
			"amount",
			0
		)
	)


	match cost_type:

		"lose_power":

			var current_power = int(
				game.players[
					player_index
				].power
			)

			if current_power < amount:
				print(
					"Cannot pay Room cost"
				)

				return true


			game.add_player_power(
				player_index,
				-amount
			)


		_:
			print(
				"Unknown Room payment type: ",
				cost_type
			)

			return false


	return resolve_effects(
		effect.get(
			"effects",
			[]
		),
		context
	)


# =========================================================
# MOVEMENT
# =========================================================

func _resolve_move(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	if amount <= 0:
		return true


	# =====================================================
	# MULTIPLE MOVES
	#
	# Example Forge:
	#
	# "destination_room_ids": [
	#     "room_a",
	#     "room_b",
	#     "room_c",
	#     "room_d"
	# ]
	# =====================================================

	if context.has(
		"destination_room_ids"
	):

		var destinations = context[
			"destination_room_ids"
		]

		if not destinations is Array:

			print(
				"Room Move: destination_room_ids is not an Array"
			)

			return false


		var move_index: int = int(
			context.get(
				"_room_move_index",
				0
			)
		)


		if move_index >= destinations.size():

			print(
				"Room Move: not enough destinations"
			)

			return false


		var destination_room_id: String = str(
			destinations[
				move_index
			]
		)


		if destination_room_id.is_empty():

			print(
				"Room Move: empty destination"
			)

			return false


		var success: bool = (
			game.move_mage_to_room_id(
				player_index,
				destination_room_id,
				amount
			)
		)


		if not success:
			return false


		context[
			"_room_move_index"
		] = move_index + 1


		return true


	# =====================================================
	# SINGLE MOVE
	# =====================================================

	var destination_room_id: String = str(
		context.get(
			"destination_room_id",
			""
		)
	)


	if destination_room_id.is_empty():

		print(
			"Room Move: destination not chosen"
		)

		return false


	return game.move_mage_to_room_id(
		player_index,
		destination_room_id,
		amount
	)


# =========================================================
# CARD EFFECTS
# =========================================================

func _resolve_discard_spells(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	if amount <= 0:
		return true


	var selected_spell_ids = context.get(
		"discard_spell_ids",
		[]
	)
	if selected_spell_ids is String:
		selected_spell_ids = [selected_spell_ids]


	if not selected_spell_ids is Array:

		print(
			"discard_spells: invalid discard_spell_ids"
		)

		return false


	if selected_spell_ids.size() != amount:

		print(
			"discard_spells: Player ",
			player_index + 1,
			" must select ",
			amount,
			" Spell(s), selected ",
			selected_spell_ids.size()
		)

		return false


	var success = game.discard_player_spells_by_id(
		player_index,
		selected_spell_ids
	)


	if not success:

		print(
			"discard_spells: invalid Spell selection"
		)

		return false


	print(
		"Player ",
		player_index + 1,
		" discarded ",
		amount,
		" Spell(s)"
	)


	return true


# =========================================================
# QUEST / FORGOTTEN DECK EFFECTS
# =========================================================

func _resolve_draw_quest(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	var player_index := _player_index(context)
	if game == null or player_index < 0 or player_index >= game.players.size():
		return false
	for i in range(maxi(0, int(effect.get("amount", 1)))):
		if game.quest_manager.draw_quest(game, player_index) == null:
			break
	return true


func _resolve_discard_quest(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	var player_index := _player_index(context)
	if game == null or player_index < 0 or player_index >= game.players.size():
		return false
	var selected_value = context.get("room_discard_quests", [])
	var selected: Array = selected_value if selected_value is Array else [selected_value]
	var amount := mini(maxi(0, int(effect.get("amount", 1))), game.players[player_index].active_quests.size())
	if selected.size() != amount:
		return false
	var seen: Array = []
	for quest in selected:
		if not game.players[player_index].active_quests.has(quest) or seen.has(quest):
			return false
		seen.append(quest)
	for quest in selected:
		game.quest_manager.discard_active_quest(game, player_index, quest)
	return true


func _resolve_draw_forgotten(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	var player_index := _player_index(context)
	if game == null or player_index < 0 or player_index >= game.players.size():
		return false
	for i in range(maxi(0, int(effect.get("amount", 1)))):
		if game.draw_forgotten_spell(player_index) == null:
			break
	return true


func _resolve_draw_forgotten_choose(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	if game == null:
		return false
	if game.forgotten_deck.is_empty():
		return true
	# Reuse the existing draw-N/keep-one primitive and Forgotten removal rules.
	if int(effect.get("keep", 1)) != 1:
		return false
	return game.effect_resolver._resolve_draw_three_forgotten_keep_one(effect, context)


func _resolve_library_draw_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var school_id: String = str(
		context.get(
			"school_id",
			""
		)
	)

	var chosen_spell_id: String = str(
		context.get(
			"chosen_spell_id",
			""
		)
	)


	if school_id.is_empty():

		print(
			"library_draw_choice: school selection required"
		)

		return false


	if not game.is_school_active(
		school_id
	):

		print(
			"library_draw_choice: school is not active: ",
			school_id
		)

		return false


	var look_at: int = int(
		effect.get(
			"look_at",
			4
		)
	)

	var keep: int = int(
		effect.get(
			"keep",
			1
		)
	)


	if keep != 1:

		print(
			"library_draw_choice: only keep = 1 is currently supported"
		)

		return false


	var revealed: Array[SpellCardState] = []


	for i in range(
		look_at
	):

		var spell: SpellCardState = (
			game.draw_from_school_library(
				school_id
			)
		)


		if spell == null:
			break


		revealed.append(
			spell
		)


	if revealed.is_empty():

		print(
			"library_draw_choice: no cards available in Library"
		)

		return true


	if chosen_spell_id.is_empty():

		print(
			"library_draw_choice: Spell selection required"
		)

		# Rimettiamo le carte nella Library
		# perché l'effetto non è stato risolto.

		var library = game.get_school_library(
			school_id
		)


		for spell in revealed:

			library.append(
				spell
			)


		return false


	var chosen_spell: SpellCardState = null


	for spell in revealed:

		if spell.id == chosen_spell_id:

			chosen_spell = spell
			break


	if chosen_spell == null:

		print(
			"library_draw_choice: selected Spell was not among revealed cards: ",
			chosen_spell_id
		)


		var library = game.get_school_library(
			school_id
		)


		for spell in revealed:

			library.append(
				spell
			)


		return false


	# =====================================================
	# KEEP CHOSEN CARD
	# =====================================================

	game.players[
		player_index
	].hand.append(
		chosen_spell
	)


	print(
		"Player ",
		player_index + 1,
		" kept ",
		chosen_spell.card_name,
		" from ",
		school_id,
		" Library"
	)


	# =====================================================
	# DISCARD ALL OTHER REVEALED CARDS
	# =====================================================

	for spell in revealed:

		if spell == chosen_spell:
			continue


		game.discard_to_school(
			school_id,
			spell
		)


	return true
	
func _resolve_search_grimoire(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var keyword: String = str(
		effect.get(
			"keyword",
			""
		)
	)


	var candidates: Array[SpellCardState] = []


	match keyword:

		"summon":

			candidates = (
				game.get_summon_spells_from_grimoire(
					player_index
				)
			)


		"":

			for spell in game.players[
				player_index
			].grimoire:

				candidates.append(
					spell
				)


		_:

			print(
				"search_grimoire: unsupported keyword ",
				keyword
			)

			return false


	if candidates.is_empty():

		print(
			"search_grimoire: no matching Spell found"
		)

		return true


	var chosen_spell_id: String = str(
		context.get(
			"chosen_spell_id",
			""
		)
	)


	if chosen_spell_id.is_empty():

		print(
			"search_grimoire: Spell selection required"
		)

		return false


	var valid_choice: bool = false


	for spell in candidates:

		if spell.id == chosen_spell_id:

			valid_choice = true
			break


	if not valid_choice:

		print(
			"search_grimoire: selected Spell is not a valid candidate: ",
			chosen_spell_id
		)

		return false


	var drawn_spell = (
		game.draw_specific_spell_from_grimoire(
			player_index,
			chosen_spell_id
		)
	)


	if drawn_spell == null:
		return false


	print(
		"Player ",
		player_index + 1,
		" selected ",
		drawn_spell.card_name,
		" from Grimoire"
	)


	return true
func _resolve_search_personal_spell(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var source: String = str(
		context.get(
			"spell_source",
			""
		)
	)

	var chosen_spell_id: String = str(
		context.get(
			"chosen_spell_id",
			""
		)
	)


	if source != "grimoire" \
	and source != "memories":

		print(
			"search_personal_spell: source selection required"
		)

		return false


	if chosen_spell_id.is_empty():

		print(
			"search_personal_spell: Spell selection required"
		)

		return false


	var spell = game.search_personal_spell(
		player_index,
		chosen_spell_id,
		source
	)


	if spell == null:

		print(
			"search_personal_spell: selected Spell not found"
		)

		return false


	return true
func _resolve_search_grimoire_or_memories(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var source: String = str(
		context.get(
			"spell_source",
			""
		)
	)

	var chosen_spell_id: String = str(
		context.get(
			"chosen_spell_id",
			""
		)
	)


	if source != "grimoire" \
	and source != "memories":

		print(
			"search_grimoire_or_memories: source selection required"
		)

		return false


	if chosen_spell_id.is_empty():

		print(
			"search_grimoire_or_memories: Spell selection required"
		)

		return false


	var spell = game.search_personal_spell(
		player_index,
		chosen_spell_id,
		source
	)


	if spell == null:

		print(
			"search_grimoire_or_memories: selected Spell not found"
		)

		return false


	# Dopo aver preso la carta scelta,
	# tutte le Memories residue tornano nel Grimoire
	# e il Grimoire viene rimescolato.

	if not game.shuffle_memories_into_grimoire(
		player_index
	):

		return false


	return true

func _resolve_replace_revealed_spell_from_hand(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get(
		"game",
		null
	)

	var player_index: int = int(
		context.get(
			"player_index",
			-1
		)
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var revealed_spell_id: String = str(
		context.get(
			"revealed_spell_id",
			""
		)
	)

	var hand_spell_id: String = str(
		context.get(
			"hand_spell_id",
			""
		)
	)


	if revealed_spell_id.is_empty():

		print(
			"replace_revealed_spell_from_hand: "
			+ "revealed Spell selection required"
		)

		return false


	if hand_spell_id.is_empty():

		print(
			"replace_revealed_spell_from_hand: "
			+ "Hand Spell selection required"
		)

		return false


	return game.replace_revealed_spell_from_hand(
		player_index,
		revealed_spell_id,
		hand_spell_id
	)
func _resolve_discard_spell(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)


	if not _valid_player(
		game,
		player_index
	):
		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)

	var destination: String = str(
		effect.get(
			"destination",
			"memories"
		)
	)


	if amount != 1:

		print(
			"discard_spell: only amount = 1 is currently supported"
		)

		return false


	var chosen_spell_id: String = str(
		context.get(
			"discard_spell_id",
			""
		)
	)


	if chosen_spell_id.is_empty():

		print(
			"discard_spell: Spell selection required"
		)

		return false


	var player = game.players[
		player_index
	]

	var chosen_spell: SpellCardState = null


	for spell in player.hand:

		if spell.id == chosen_spell_id:

			chosen_spell = spell
			break


	if chosen_spell == null:

		print(
			"discard_spell: selected Spell not found in Hand: ",
			chosen_spell_id
		)

		return false


	match destination:

		"memories":

			return game.discard_player_spell(
				player_index,
				chosen_spell
			)


		_:

			print(
				"discard_spell: unsupported destination ",
				destination
			)

			return false
func _resolve_cast_next_ready_spell(
	_effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)


	if not _valid_player(
		game,
		player_index
	):
		return false


	return game.cast_next_ready_spell(
		player_index,
		context
	)
func _resolve_draw_library(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)


	if game == null:
		return false


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	if amount <= 0:
		return true


	# =====================================================
	# SCHOOL SELECTION
	#
	# Per ogni carta pescata dalla Library viene indicata
	# la Scuola da cui pescare.
	#
	# Esempio Bibliotheca:
	#
	# "library_school_ids": [
	#     "agony",
	#     "alchemy"
	# ]
	#
	# Può anche essere la stessa Scuola due volte.
	# =====================================================

	var school_ids: Array = context.get(
		"library_school_ids",
		[]
	)


	if school_ids.size() < amount:

		print(
			"draw_library: ",
			amount,
			" school selections required"
		)

		return false


	# =====================================================
	# VALIDATE ALL CHOICES FIRST
	#
	# Evitiamo di pescare la prima carta e poi fallire
	# sulla seconda scelta.
	# =====================================================

	for i in range(amount):

		var school_id: String = str(
			school_ids[i]
		)


		if school_id.is_empty():

			print(
				"draw_library: empty school selection"
			)

			return false


		if not game.is_school_active(
			school_id
		):

			print(
				"draw_library: inactive school: ",
				school_id
			)

			return false


	# =====================================================
	# DRAW
	# =====================================================

	for i in range(amount):

		var school_id: String = str(
			school_ids[i]
		)


		var spell: SpellCardState = (
			game.draw_from_school_library(
				school_id
			)
		)


		if spell == null:

			print(
				"draw_library: no Spell available from ",
				school_id
			)

			return false


		game.players[
			player_index
		].hand.append(
			spell
		)


		print(
			"Player ",
			player_index + 1,
			" drew ",
			spell.card_name,
			" from ",
			school_id,
			" Library"
		)


	return true

func _resolve_attack(
	_effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var attacker_mage = game.players[
		player_index
	].mage


	# =====================================================
	# TARGET
	#
	# Supportiamo più Attack consecutivi.
	#
	# Forge può quindi ricevere:
	#
	# "attack_target_player_indices": [1, 2]
	# =====================================================

	var target_player_index: int = -1


	if context.has(
		"attack_target_player_indices"
	):

		var targets = context[
			"attack_target_player_indices"
		]

		if not targets is Array:

			print(
				"Room Attack: attack_target_player_indices is not an Array"
			)

			return false


		var attack_index: int = int(
			context.get(
				"_room_attack_index",
				0
			)
		)


		if attack_index >= targets.size():

			print(
				"Room Attack: not enough targets"
			)

			return false


		target_player_index = int(
			targets[
				attack_index
			]
		)


		context[
			"_room_attack_index"
		] = attack_index + 1


	else:

		target_player_index = int(
			context.get(
				"target_player_index",
				-1
			)
		)


	if not _valid_player(
		game,
		target_player_index
	):

		print(
			"Room Attack: invalid target"
		)

		return false


	# Non puoi attaccare te stesso.
	if target_player_index == player_index:

		print(
			"Room Attack: Mage cannot attack itself"
		)

		return false


	var target_mage = game.players[
		target_player_index
	].mage


	# =====================================================
	# RANGE 0
	#
	# Attack della Forge:
	# il bersaglio deve trovarsi nella stessa Room.
	# =====================================================

	if target_mage.in_cell:

		print(
			"Room Attack: target Mage is in its Cell"
		)

		return false


	if attacker_mage.room_id != target_mage.room_id:

		print(
			"Room Attack: target Mage is not in the same Room"
		)

		return false


	# =====================================================
	# STRENGTH
	# =====================================================

	var damage_amount: int = (
		attacker_mage.strength
	)


	if damage_amount <= 0:

		print(
			"Room Attack: Mage Strength is ",
			damage_amount
		)

		return false


	# =====================================================
	# DAMAGE
	#
	# Passiamo dalla normale pipeline di Damage.
	# action_type = "attack" permette ai trigger futuri
	# di distinguere un Attack da altri Damage.
	# =====================================================

	game.deal_damage(
		player_index,
		target_player_index,
		damage_amount,
		"attack"
	)


	return true

func _resolve_return_all_mages_to_cells(
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	return game.return_all_mages_to_cells()

func _resolve_copy_room_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)

	if not _valid_player(
		game,
		player_index
	):
		return false


	var copied_room_id: String = str(
		context.get(
			"copied_room_id",
			""
		)
	)


	if copied_room_id.is_empty():

		print(
			"Mirrors Room: copied Room missing"
		)

		return false


	var excluded: Array = effect.get(
		"exclude",
		[]
	)


	if copied_room_id in excluded:

		print(
			"Mirrors Room: Room cannot be copied: ",
			copied_room_id
		)

		return false


	if copied_room_id == "mirrors_room":

		print(
			"Mirrors Room: cannot copy itself"
		)

		return false


	var copied_room = game.get_room_by_id(
		copied_room_id
	)


	if copied_room == null:

		print(
			"Mirrors Room: Room not found: ",
			copied_room_id
		)

		return false


	var copied_effects: Array = copied_room.room_data.get(
		"rebuilt_effects",
		[]
	)


	if copied_effects.is_empty():

		print(
			"Mirrors Room: copied Room has no rebuilt effects"
		)

		return false


	print(
		"Mirrors Room copies ",
		copied_room.room_name
	)


	return resolve_effects(
		copied_effects,
		context
	)
func _resolve_take_crown(
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	var player_index: int = _player_index(
		context
	)


	if not _valid_player(
		game,
		player_index
	):
		return false


	return game.take_crown(
		player_index
	)
func _resolve_draw_event(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(
		context
	)

	if game == null:
		return false


	var player_index: int = _player_index(
		context
	)


	if player_index < 0 \
	or player_index >= game.players.size():

		return false


	var amount: int = int(
		effect.get(
			"amount",
			1
		)
	)


	for i in range(
		amount
	):

		var event = game.draw_event(
			player_index,
			context
		)


		if event == null:
			return false


	return true
