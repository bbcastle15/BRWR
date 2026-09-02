class_name EffectResolver
extends RefCounted

func resolve_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var effect_type = str(effect.get("type", ""))

	match effect_type:
		"damage":
			return resolve_damage(effect, context)

		"heal":
			return resolve_heal(effect, context)

		"gain_power":
			return resolve_gain_power(effect, context)

		"lose_power":
			return resolve_lose_power(effect, context)

		"place_instability":
			return resolve_place_instability(effect, context)
		
		"damage_per_black_rose_damage":
			return resolve_damage_per_black_rose_damage(effect, context)

		"pain":
			return resolve_pain(effect, context)
			
		"convert_damage":
			return resolve_convert_damage(effect, context)
			
		"summon_evocation":
			return resolve_summon_evocation(
				effect,
				context
			)
		"activate_summoned_evocation":
			return resolve_activate_summoned_evocation(
				effect,
				context
			)
		"damage_from_evocation":
			return resolve_damage_from_evocation(effect, context)

		"remove_target_evocation":
			return resolve_remove_target_evocation(effect, context)
		"damage_triggering_model":
			return resolve_damage_triggering_model(
				effect,
				context
			)
		"summon_evocation_at_triggering_model":
			return resolve_summon_evocation_at_triggering_model(
				effect,
				context
			)
		"damage_triggering_model_from_trigger_damage":
			return resolve_damage_triggering_model_from_trigger_damage(
				effect,
				context
			)
		"conditional":
			return resolve_conditional(
				effect,
				context
			)
		"damage_all_target_owner_evocations":
			return resolve_damage_all_target_owner_evocations(
				effect,
				context
				)
		"convert_damage_on_caster":
			return resolve_convert_damage_on_caster(
				effect,
				context
			)

		"damage_secondary_mage_per_self_damage":
			return resolve_damage_secondary_mage_per_self_damage(
				effect,
				context
			)
		"damage_marked_mage":
			return resolve_damage_marked_mage(
				effect,
				context
			)
		"redirect_damage_to_evocation":
			return resolve_redirect_damage_to_evocation(
				effect,
				context
			)
		"pain_from_trigger_damage":
			return resolve_pain_from_trigger_damage(
				effect,
				context
			)

		"gain_power_per_black_rose_damage":
			return resolve_gain_power_per_black_rose_damage(
				effect,
				context
			)
		"gain_power_from_defeating_model":
			return resolve_gain_power_from_defeating_model(
				effect,
				context
			)
		"place_instability_at_defeated_mage_room_per_self_damage":
			return resolve_place_instability_at_defeated_mage_room_per_self_damage(
				effect,
				context
			)
		"place_instability_per_black_rose_damage_on_effect_damaged_models":
			return resolve_place_instability_per_black_rose_damage_on_effect_damaged_models(
				effect,
				context
			)
		"place_instability_per_self_black_rose_damage":
			return resolve_place_instability_per_self_black_rose_damage(
				effect,
				context
			)
		"damage_marked_mage":
			return resolve_damage_marked_mage(
				effect,
				context
			)
		"damage_per_revealed_active_element":
			return resolve_damage_per_revealed_active_element(
				effect,
				context
			)
		"modify_spell_target":
			return resolve_modify_spell_target(
				effect,
				context
			)

		"move_one_model_damaged_by_effect":
			return resolve_move_one_model_damaged_by_effect(
				effect,
				context
			)
		"place_instability_per_revealed_active_element":
			return resolve_place_instability_per_revealed_active_element(
				effect,
				context
			)
		"damage_all_models_of_type":
			return resolve_damage_all_models_of_type(
				effect,
				context
			)
		"summon_same_evocation_as_trigger":
			return resolve_summon_same_evocation_as_trigger(
				effect,
				context
			)
		"activate_room_from_owned_evocation":
			return resolve_activate_room_from_owned_evocation(
				effect,
				context
			)
		"remove_owned_evocation":
			return resolve_remove_owned_evocation(
				effect,
				context
			)

		"summon_evocation_from_deck":
			return resolve_summon_evocation_from_deck(
				effect,
				context
			)
		"remove_owned_evocation_and_damage_around":
			return resolve_remove_owned_evocation_and_damage_around(
				effect,
				context
			)
		"damage_models_damaged_by_effect":
			return resolve_damage_models_damaged_by_effect(
				effect,
				context
			)
		"activate_owned_evocation":
			return resolve_activate_owned_evocation(
				effect,
				context
			)
		"remove_evocation_with_max_health":
			return resolve_remove_evocation_with_max_health(
				effect,
				context
			)

		"summon_evocation_at_removed_evocation":
			return resolve_summon_evocation_at_removed_evocation(
				effect,
				context
			)
		"fountain_construct_or_nigredo":
			return resolve_fountain_construct_or_nigredo(
				effect,
				context
			)
		"heal_target_evocation":
			return resolve_heal_target_evocation(
				effect,
				context
			)
		"next_activation_strength_bonus":
			return resolve_next_activation_strength_bonus(
				effect,
				context
			)
		"activate_target_evocation":
			return resolve_activate_target_evocation(
				effect,
				context
			)
		"activate_target_evocation_under_control":
			return resolve_activate_target_evocation_under_control(
				effect,
				context
			)
		"ignore_trigger_damage":
			return resolve_ignore_trigger_damage(
				effect,
				context
			)
		"activate_owned_evocation_then_black_rose_damage":
			return resolve_activate_owned_evocation_then_black_rose_damage(
				effect,
				context
			)
		"silver_defeat_choice":
			return resolve_silver_defeat_choice(
				effect,
				context
			)
		_:
			print("UNKNOWN EFFECT TYPE: ", effect_type)
			return false

func resolve_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get("caster_id", -999)
	)

	var amount = int(
		effect.get("amount", 0)
	)


	# =====================================================
	# TRIGGER SOPPRESSI DA QUESTA SPECIFICA ISTANZA
	# DI DAMAGE
	#
	# Esempio Athanor Eruption:
	# ["protection", "trap"]
	# =====================================================

	var suppressed_trigger_types: Array[String] = []

	for trigger_type in effect.get(
		"suppress_triggers",
		[]
	):
		suppressed_trigger_types.append(
			str(trigger_type)
		)


	if amount <= 0:
		return true


	# =====================================================
	# ASSICURIAMOCI CHE IL TRACKING ESISTA
	#
	# resolve_spell() normalmente lo inizializza,
	# ma così manteniamo compatibilità anche con vecchi
	# test che chiamano direttamente EffectResolver.
	# =====================================================

	if not context.has(
		"models_damaged_by_effect"
	):
		context["models_damaged_by_effect"] = []


	var target_type = str(
		context.get(
			"spell_target_type",
			""
		)
	)


	# =====================================================
	# RETROCOMPATIBILITÀ
	#
	# Le vecchie Spell/test possono avere soltanto
	# target_player_index.
	# =====================================================

	if target_type == "" \
	and context.has("target_player_index"):

		target_type = "mage"


	# =====================================================
	# TARGET = ROOM
	#
	# Tutti i Models presenti nella Room subiscono Damage.
	# =====================================================

	if target_type == "room":

		var room_id = str(
			context.get(
				"target_room_id",
				context.get(
					"room_id",
					""
				)
			)
		)

		if room_id == "":
			print(
				"resolve_damage: target Room missing"
			)
			return false


		# -------------------------------------------------
		# MAGE NELLA ROOM
		# -------------------------------------------------

		for player_index in range(
			game.players.size()
		):

			var mage = (
				game.players[player_index]
				.mage
			)

			if mage.room_id != room_id:
				continue


			var damage_dealt = (
				game.deal_damage(
					caster_id,
					player_index,
					amount,
					"spell",
					suppressed_trigger_types
				)
			)


			if damage_dealt > 0:
				register_damaged_model(
					context,
					{
						"type": "mage",
						"player_index":
							player_index,
						"room_id":
							room_id
					}
				)


		# -------------------------------------------------
		# EVOCATIONS NELLA ROOM
		# -------------------------------------------------

		for player in game.players:

			for evocation in player.evocations:

				if evocation.room_id != room_id:
					continue


				var damage_dealt = (
					game.deal_damage_to_evocation(
						caster_id,
						evocation,
						amount,
						suppressed_trigger_types
					)
				)


				if damage_dealt > 0:
					register_damaged_model(
						context,
						{
							"type":
								"evocation",
							"evocation":
								evocation,
							"room_id":
								room_id
						}
					)


		return true


	# =====================================================
	# TARGET = EVOCATION
	# =====================================================

	if target_type == "evocation":

		var target_evocation = context.get(
			"target_evocation"
		)

		if target_evocation == null:
			print(
				"resolve_damage: target Evocation missing"
			)
			return false


		var damage_dealt = (
			game.deal_damage_to_evocation(
				caster_id,
				target_evocation,
				amount,
				suppressed_trigger_types
			)
		)


		context["last_damage_dealt"] = (
			damage_dealt
		)


		if damage_dealt > 0:

			context["last_damaged_model_type"] = (
				"evocation"
			)

			context["last_damaged_evocation"] = (
				target_evocation
			)


			register_damaged_model(
				context,
				{
					"type": "evocation",
					"evocation":
						target_evocation,
					"room_id":
						target_evocation.room_id
				}
			)


		return true


	# =====================================================
	# TARGET = MODEL
	#
	# MODEL può essere:
	# - Mage
	# - Evocation
	# =====================================================

	if target_type == "model":

		var model_type = str(
			context.get(
				"target_model_type",
				""
			)
		)


		# -------------------------------------------------
		# RETROCOMPATIBILITÀ:
		# se c'è target_player_index e nessun tipo,
		# assumiamo Mage.
		# -------------------------------------------------

		if model_type == "" \
		and context.has(
			"target_player_index"
		):

			model_type = "mage"


		# ---------------------------------------------
		# MODEL = MAGE
		# ---------------------------------------------

		if model_type == "mage":

			var target_player_index = int(
				context.get(
					"target_player_index",
					-1
				)
			)

			if target_player_index < 0 \
			or target_player_index >= game.players.size():
				return false


			var damage_dealt = (
				game.deal_damage(
					caster_id,
					target_player_index,
					amount,
					"spell",
					suppressed_trigger_types
				)
			)


			context["last_damage_dealt"] = (
				damage_dealt
			)

			context[
				"last_damage_target_player_index"
			] = target_player_index

			context[
				"last_damage_defeated_target"
			] = (
				game.players[
					target_player_index
				]
				.mage
				.is_defeated()
			)


			if damage_dealt > 0:

				context[
					"last_damaged_model_type"
				] = "mage"

				context[
					"last_damaged_player_index"
				] = target_player_index


				register_damaged_model(
					context,
					{
						"type": "mage",
						"player_index":
							target_player_index,
						"room_id":
							game.players[
								target_player_index
							]
							.mage
							.room_id
					}
				)


			return true


		# ---------------------------------------------
		# MODEL = EVOCATION
		# ---------------------------------------------

		if model_type == "evocation":

			var target_evocation = (
				context.get(
					"target_evocation"
				)
			)

			if target_evocation == null:
				print(
					"resolve_damage: target Model Evocation missing"
				)
				return false


			var damage_dealt = (
				game.deal_damage_to_evocation(
					caster_id,
					target_evocation,
					amount,
					suppressed_trigger_types
				)
			)


			context["last_damage_dealt"] = (
				damage_dealt
			)


			if damage_dealt > 0:

				context[
					"last_damaged_model_type"
				] = "evocation"

				context[
					"last_damaged_evocation"
				] = target_evocation


				register_damaged_model(
					context,
					{
						"type":
							"evocation",
						"evocation":
							target_evocation,
						"room_id":
							target_evocation.room_id
					}
				)


			return true


		print(
			"resolve_damage: unknown Model type: ",
			model_type
		)

		return false


	# =====================================================
	# TARGET = MAGE
	# =====================================================

	if target_type == "mage":

		var target_player_index = int(
			context.get(
				"target_player_index",
				-1
			)
		)

		if target_player_index < 0 \
		or target_player_index >= game.players.size():

			return false


		var damage_dealt = game.deal_damage(
			caster_id,
			target_player_index,
			amount,
			"spell",
			suppressed_trigger_types
		)


		# -------------------------------------------------
		# Stato dell'ultimo Damage.
		#
		# Serve ancora per:
		# - Visceral Fire
		# - Submission
		# - effetti condizionali
		# -------------------------------------------------

		context["last_damage_dealt"] = (
			damage_dealt
		)

		context[
			"last_damage_target_player_index"
		] = target_player_index

		context[
			"last_damage_defeated_target"
		] = (
			game.players[
				target_player_index
			]
			.mage
			.is_defeated()
		)


		if damage_dealt > 0:

			context[
				"last_damaged_model_type"
			] = "mage"

			context[
				"last_damaged_player_index"
			] = target_player_index


			register_damaged_model(
				context,
				{
					"type": "mage",
					"player_index":
						target_player_index,
					"room_id":
						game.players[
							target_player_index
						]
						.mage
						.room_id
				}
			)


		return true


	# =====================================================
	# TARGET TYPE NON SUPPORTATO
	# =====================================================

	print(
		"resolve_damage: unsupported target type: ",
		target_type
	)

	return false
	
func resolve_heal(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var owner_id = int(
		effect.get(
			"owner_id",
			context.get("damage_owner_id", -999)
		)
	)

	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if target_player_index < 0:
		return false

	game.heal_damage(
		target_player_index,
		owner_id,
		amount
	)

	return true
	
func resolve_gain_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(context.get("caster_id", -999))
	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if caster_id == -1:
		game.add_black_rose_power(amount)
	else:
		game.add_player_power(
			caster_id,
			amount
		)

	return true
	
func resolve_lose_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if target_player_index < 0:
		return false

	game.add_player_power(
		target_player_index,
		-amount
	)

	return true
	
func resolve_place_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(
		context.get("caster_id", -999)
	)

	var room_id = str(
		context.get(
			"target_room_id",
			context.get("room_id", "")
		)
	)

	var amount = int(
		effect.get("amount", 1)
	)

	if game == null:
		return false

	if room_id == "":
		print(
			"place_instability: target Room missing"
		)
		return false

	if caster_id == -1:
		game.place_black_rose_instability(
			room_id,
			amount
		)
	else:
		game.place_player_instability(
			caster_id,
			room_id,
			amount
		)

	return true
	
func resolve_effects(
	effects: Array,
	context: Dictionary
) -> bool:

	for effect in effects:
		if not resolve_effect(effect, context):
			return false

	return true
	
func resolve_pain(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(context.get("caster_id", -1))
	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	if amount <= 0:
		return true

	game.deal_damage(
		-1,
		caster_id,
		amount
	)

	print(
		"Pain ",
		amount,
		": Black Rose -> Player ",
		caster_id + 1
	)

	return true
	
func resolve_damage_per_black_rose_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	if target_player_index < 0:
		return false

	var caster_mage = game.players[caster_id].mage

	var black_rose_damage = caster_mage.get_damage_from(-1)

	var step = int(effect.get("step", 1))
	var damage_per_step = int(
		effect.get("damage_per_step", 1)
	)
	var max_damage = int(
		effect.get("max", 999)
	)

	if step <= 0:
		return false

	var amount = (
		int(black_rose_damage / step)
		* damage_per_step
	)

	amount = min(amount, max_damage)

	if amount <= 0:
		return true

	game.deal_damage(
		caster_id,
		target_player_index,
		amount
	)

	return true
	
func resolve_convert_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true


	var target_type = str(
		context.get(
			"spell_target_type",
			""
		)
	)


	# =====================================================
	# TARGET = MAGE
	# =====================================================

	if target_type == "mage":

		var target_player_index = int(
			context.get(
				"target_player_index",
				-1
			)
		)

		if target_player_index < 0 \
		or target_player_index >= game.players.size():
			return false


		var mage = (
			game.players[
				target_player_index
			].mage
		)


		var converted = convert_damage_cubes(
			mage.damage_cubes,
			caster_id,
			amount
		)


		if target_player_index < game.player_boards.size():

			game.player_boards[
				target_player_index
			].refresh()


		print(
			"Convert damage: P",
			caster_id + 1,
			" converted ",
			converted,
			" Damage on P",
			target_player_index + 1
		)


		return true


	# =====================================================
	# TARGET = EVOCATION
	# =====================================================

	if target_type == "evocation":

		var target_evocation = context.get(
			"target_evocation"
		)

		if target_evocation == null:
			return false


		var converted = convert_damage_cubes(
			target_evocation.damage_cubes,
			caster_id,
			amount
		)


		print(
			"Convert damage: P",
			caster_id + 1,
			" converted ",
			converted,
			" Damage on ",
			target_evocation.evocation_name
		)


		return true


	# =====================================================
	# TARGET = ROOM
	#
	# Convert up to the indicated amount on EACH Model
	# in the target Room.
	# =====================================================

	if target_type == "room":

		var target_room_id = str(
			context.get(
				"target_room_id",
				""
			)
		)

		if target_room_id == "":
			return false


		# -------------------------------------------------
		# MAGES
		# -------------------------------------------------

		for player_index in range(
			game.players.size()
		):

			var mage = (
				game.players[
					player_index
				].mage
			)


			if mage.room_id != target_room_id:
				continue


			if game.is_mage_in_cell(
				player_index
			):
				continue


			var converted = convert_damage_cubes(
				mage.damage_cubes,
				caster_id,
				amount
			)


			if player_index < game.player_boards.size():

				game.player_boards[
					player_index
				].refresh()


			print(
				"Albify Room: converted ",
				converted,
				" Damage on P",
				player_index + 1
			)


		# -------------------------------------------------
		# EVOCATIONS
		# -------------------------------------------------

		for player in game.players:

			for evocation in player.evocations:

				if evocation == null:
					continue

				if evocation.is_defeated():
					continue

				if evocation.room_id != target_room_id:
					continue


				var converted = convert_damage_cubes(
					evocation.damage_cubes,
					caster_id,
					amount
				)


				print(
					"Albify Room: converted ",
					converted,
					" Damage on ",
					evocation.evocation_name
				)


		return true


	print(
		"resolve_convert_damage: unsupported target type: ",
		target_type
	)

	return false

func resolve_summon_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-999
		)
	)


	if caster_id < 0:
		print(
			"summon_evocation: invalid caster"
		)
		return false


	var evocation_id = str(
		effect.get(
			"evocation_id",
			""
		)
	)


	if evocation_id == "":
		print(
			"summon_evocation: missing evocation_id"
		)
		return false


	# =====================================================
	# DETERMINE SUMMON ROOM
	# =====================================================

	var room_mode = str(
		effect.get(
			"room",
			""
		)
	)


	var room_id = ""


	match room_mode:

		"trigger_evocation_room":

			room_id = str(
				context.get(
					"trigger_evocation_room_id",
					""
				)
			)


		"caster_room":

			room_id = str(
				context.get(
					"caster_room_id",
					""
				)
			)


		_:

			room_id = str(
				context.get(
					"target_room_id",
					""
				)
			)


	if room_id == "":
		print(
			"summon_evocation: missing summon Room"
		)
		return false


	# =====================================================
	# SUMMON
	# =====================================================

	var evocation = game.summon_evocation(
		caster_id,
		evocation_id,
		room_id
	)


	if evocation == null:

		print(
			"summon_evocation: failed to summon ",
			evocation_id
		)

		return false


	context["last_summoned_evocation"] = (
		evocation
	)


	print(
		"Summoned ",
		evocation.evocation_name,
		" from spell effect in ",
		room_id
	)


	return true
	
func resolve_activate_summoned_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var evocation = context.get(
		"last_summoned_evocation"
	)

	if evocation == null:
		return false

	print(
		evocation.evocation_name,
		" activates"
	)

	return true

func resolve_damage_from_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(context.get("caster_id", -1))
	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var target_evocation = context.get(
		"target_evocation"
	)

	if game == null:
		return false

	if target_evocation == null:
		print("damage_from_evocation: target_evocation missing")
		return false

	if target_player_index < 0:
		print("damage_from_evocation: target_player_index missing")
		return false

	var base_amount = int(
		effect.get("base_amount", 0)
	)

	var bonus_per_damage = int(
		effect.get(
			"bonus_per_evocation_damage",
			0
		)
	)

	var amount = (
		base_amount
		+ target_evocation.get_damage()
		* bonus_per_damage
	)

	game.deal_damage(
		caster_id,
		target_player_index,
		amount
	)

	print(
		"Cross and Delight: ",
		amount,
		" damage using ",
		target_evocation.evocation_name,
		" with ",
		target_evocation.get_damage(),
		" damage"
	)

	return true
	
func resolve_remove_target_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	var target_evocation = context.get(
		"target_evocation"
	)


	if game == null:
		return false


	if target_evocation == null:
		return false


	# =====================================================
	# OWNER DELLA EVOCATION
	#
	# Non assumiamo che appartenga al caster.
	# Usiamo direttamente owner_id della Evocation.
	# =====================================================

	var owner_id = target_evocation.owner_id


	if owner_id < 0 \
	or owner_id >= game.players.size():

		print(
			"remove_target_evocation: invalid owner"
		)

		return false


	var owner_player = game.players[
		owner_id
	]


	var index = owner_player.evocations.find(
		target_evocation
	)


	if index == -1:

		print(
			"remove_target_evocation: "
			+ "Evocation not found in owner's list"
		)

		return false


	# =====================================================
	# EVENT BEFORE REMOVAL
	#
	# Stone Phoenix deve ancora poter leggere:
	#
	# - evocation_id
	# - evocation_name
	# - owner_id
	# - room_id
	#
	# quindi l'evento deve essere emesso PRIMA del remove_at.
	# =====================================================

	game.emit_evocation_defeated_or_removed(
		target_evocation,
		"removed"
	)


	# =====================================================
	# REMOVE
	# =====================================================

	owner_player.evocations.remove_at(
		index
	)


	print(
		"Removed Evocation: ",
		target_evocation.evocation_name
	)


	return true

func resolve_damage_triggering_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(
		context.get("caster_id", -1)
	)

	var model_type = str(
		context.get("triggering_model_type", "")
	)

	var amount = int(
		effect.get("amount", 0)
	)

	if game == null:
		return false

	match model_type:
		"mage":
			var player_index = int(
				context.get(
					"triggering_player_index",
					-1
				)
			)

			if player_index < 0:
				return false

			game.deal_damage(
				caster_id,
				player_index,
				amount
			)

		"evocation":
			var evocation = context.get(
				"triggering_evocation"
			)

			if evocation == null:
				return false

			game.deal_damage_to_evocation(
				caster_id,
				evocation,
				amount
			)

		_:
			print(
				"Unknown triggering model type: ",
				model_type
			)
			return false

	return true
	
func resolve_summon_evocation_at_triggering_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var room_id = str(
		context.get("triggering_room_id", "")
	)

	if caster_id < 0:
		return false

	if room_id == "":
		print("Triggering model has no room")
		return false

	var evocation_id = str(
		effect.get("evocation_id", "")
	)

	var summoned = game.summon_evocation(
		caster_id,
		evocation_id,
		room_id
	)

	if summoned == null:
		return false

	context["last_summoned_evocation"] = summoned

	return true
	
func resolve_damage_triggering_model_from_trigger_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var model_type = str(
		context.get("triggering_model_type", "")
	)

	var suffered_damage = int(
		context.get("trigger_damage_amount", 0)
	)

	var bonus = int(
		effect.get("bonus", 0)
	)

	var amount = suffered_damage + bonus

	if amount <= 0:
		return true

	match model_type:
		"mage":
			var player_index = int(
				context.get(
					"triggering_player_index",
					-1
				)
			)

			if player_index < 0:
				return false

			game.deal_damage(
				caster_id,
				player_index,
				amount
			)

		"evocation":
			var evocation = context.get(
				"triggering_evocation"
			)

			if evocation == null:
				return false

			game.deal_damage_to_evocation(
				caster_id,
				evocation,
				amount
			)

		_:
			print(
				"Unknown triggering model type: ",
				model_type
			)
			return false

	print(
		"Torment retaliation: ",
		suffered_damage,
		" suffered + ",
		bonus,
		" = ",
		amount,
		" damage"
	)

	return true

func resolve_conditional(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var condition = str(
		effect.get("condition", "")
	)

	var condition_met = false

	match condition:
		"last_damage_defeated_target":
			condition_met = bool(
				context.get(
					"last_damage_defeated_target",
					false
				)
			)

		_:
			print(
				"UNKNOWN CONDITION: ",
				condition
			)
			return false

	# La condizione non verificata NON è un errore.
	if not condition_met:
		return true

	var nested_effects = effect.get(
		"effects",
		[]
	)

	return resolve_effects(
		nested_effects,
		context
	)
	
func resolve_damage_all_target_owner_evocations(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var target_player_index = int(
		context.get(
			"last_damage_target_player_index",
			-1
		)
	)

	if target_player_index < 0 \
	or target_player_index >= game.players.size():
		return false

	var amount = int(
		effect.get("amount", 0)
	)

	var target_player = game.players[
		target_player_index
	]

	# duplicate() perché qualche Evocation potrebbe essere
	# sconfitta/rimossa mentre iteriamo.
	var evocations = target_player.evocations.duplicate()

	for evocation in evocations:
		game.deal_damage_to_evocation(
			caster_id,
			evocation,
			amount
		)

	return true

func resolve_convert_damage_on_caster(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var converter_owner_id = int(
		effect.get("converter_owner_id", -1)
	)

	var amount = int(
		effect.get("amount", 0)
	)

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	if amount <= 0:
		return true

	var caster_mage = game.players[caster_id].mage

	var converted = 0

	for i in range(caster_mage.damage_cubes.size()):
		if converted >= amount:
			break

		var current_owner = caster_mage.damage_cubes[i]

		# Non serve convertire un cubo che appartiene
		# già al nuovo proprietario.
		if current_owner == converter_owner_id:
			continue

		caster_mage.damage_cubes[i] = converter_owner_id
		converted += 1

	if caster_id < game.player_boards.size():
		game.player_boards[caster_id].refresh()

	print(
		"Converted ",
		converted,
		" Damage on Player ",
		caster_id + 1,
		" to owner ",
		converter_owner_id
	)

	return true
	
func resolve_damage_secondary_mage_per_self_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var primary_target = int(
		context.get("target_player_index", -1)
	)

	var secondary_target = int(
		context.get("secondary_target_player_index", -1)
	)

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	if secondary_target < 0 \
	or secondary_target >= game.players.size():
		print(
			"Peak of Agony: secondary target missing"
		)
		return false

	# Deve essere un Mage diverso dal target originale.
	if secondary_target == primary_target:
		print(
			"Peak of Agony: secondary target "
			+ "must be different from primary target"
		)
		return false

	var self_damage = (
		game.players[caster_id]
		.mage
		.get_damage()
	)

	var step = int(
		effect.get("step", 1)
	)

	var damage_per_step = int(
		effect.get("damage_per_step", 1)
	)

	var max_damage = int(
		effect.get("max", 999)
	)

	if step <= 0:
		return false

	var amount = (
		int(self_damage / step)
		* damage_per_step
	)

	amount = min(
		amount,
		max_damage
	)

	if amount <= 0:
		return true

	game.deal_damage(
		caster_id,
		secondary_target,
		amount
	)

	print(
		"Peak of Agony secondary damage: ",
		self_damage,
		" self Damage -> ",
		amount,
		" Damage to Player ",
		secondary_target + 1
	)

	return true

func resolve_damage_marked_mage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var marked_player_index = int(
		context.get("marked_player_index", -1)
	)

	if marked_player_index < 0 \
	or marked_player_index >= game.players.size():
		return false

	var amount = int(
		effect.get("amount", 0)
	)

	game.deal_damage(
		caster_id,
		marked_player_index,
		amount,
		"spell"
	)

	return true

func resolve_redirect_damage_to_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(
		context.get("caster_id", -1)
	)

	var event: GameEvent = context.get(
		"trigger_event"
	)

	if game == null or event == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var player = game.players[caster_id]

	if player.evocations.is_empty():
		print(
			"Pain Mark: no Evocation available "
			+ "to redirect Damage"
		)
		return true

	# Per ora scegliamo automaticamente la prima Evocation.
	# Più avanti questa sarà una scelta del giocatore.
	var evocation = player.evocations[0]

	event.redirected_evocation = evocation

	print(
		"Pain Mark redirects ",
		event.amount,
		" Damage from Player ",
		caster_id + 1,
		" to ",
		evocation.evocation_name
	)

	return true

func resolve_pain_from_trigger_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var suffered_damage = int(
		context.get("trigger_damage_amount", 0)
	)

	if suffered_damage <= 0:
		return true

	game.deal_damage(
		-1,
		caster_id,
		suffered_damage,
		"spell"
	)

	print(
		"Master of Pleasure: Player ",
		caster_id + 1,
		" suffers ",
		suffered_damage,
		" Damage from Black Rose"
	)

	return true
func resolve_gain_power_per_black_rose_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var mage = game.players[caster_id].mage

	var black_rose_damage = mage.get_damage_from(-1)

	var step = int(
		effect.get("step", 1)
	)

	var power_per_step = int(
		effect.get("power_per_step", 1)
	)

	var max_power = int(
		effect.get("max", 999)
	)

	if step <= 0:
		return false

	var power_amount = (
		int(black_rose_damage / step)
		* power_per_step
	)

	power_amount = min(
		power_amount,
		max_power
	)

	if power_amount <= 0:
		return true

	game.add_player_power(
		caster_id,
		power_amount
	)

	print(
		"Master of Pleasure: ",
		black_rose_damage,
		" Black Rose Damage -> ",
		power_amount,
		" Power"
	)

	return true
func resolve_gain_power_from_defeating_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var event: GameEvent = context.get(
		"trigger_event"
	)

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if game == null or event == null:
		return false

	var amount = 0

	if event.source_model_type == "black_rose":
		amount = int(
			effect.get(
				"black_rose_amount",
				2
			)
		)
	else:
		amount = int(
			effect.get(
				"mage_amount",
				1
			)
		)

	if amount <= 0:
		return true

	game.add_player_power(
		caster_id,
		amount
	)

	print(
		"Liquefy the Pain: Player ",
		caster_id + 1,
		" gains ",
		amount,
		" Power"
	)

	return true
	
func resolve_place_instability_at_defeated_mage_room_per_self_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var event: GameEvent = context.get(
		"trigger_event"
	)

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if game == null or event == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var room_id = event.target_room_id

	if room_id == "":
		print(
			"Liquefy the Pain: defeated Mage has no Room"
		)
		return false

	var self_damage = (
		game.players[caster_id]
		.mage
		.get_damage()
	)

	var step = int(
		effect.get("step", 2)
	)

	var instability_per_step = int(
		effect.get(
			"instability_per_step",
			1
		)
	)

	var max_instability = int(
		effect.get("max", 4)
	)

	if step <= 0:
		return false

	var amount = (
		int(self_damage / step)
		* instability_per_step
	)

	amount = min(
		amount,
		max_instability
	)

	if amount <= 0:
		return true

	game.place_player_instability(
		caster_id,
		room_id,
		amount
	)

	print(
		"Liquefy the Pain: Player ",
		caster_id + 1,
		" places ",
		amount,
		" Instability in ",
		room_id
	)

	return true
func resolve_place_instability_per_black_rose_damage_on_effect_damaged_models(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(
		context.get("caster_id", -1)
	)

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var damaged_model_type = str(
		context.get("last_damaged_model_type", "")
	)

	if damaged_model_type != "mage":
		return true

	var damaged_player_index = int(
		context.get("last_damaged_player_index", -1)
	)

	if damaged_player_index < 0 \
	or damaged_player_index >= game.players.size():
		return false

	var damaged_mage = (
		game.players[damaged_player_index].mage
	)

	var black_rose_damage = (
		damaged_mage.get_damage_from(-1)
	)

	var instability_per_damage = int(
		effect.get(
			"instability_per_damage",
			1
		)
	)

	var max_instability = int(
		effect.get("max", 4)
	)

	var amount = (
		black_rose_damage
		* instability_per_damage
	)

	amount = min(
		amount,
		max_instability
	)

	if amount <= 0:
		return true

	var room_id = damaged_mage.room_id

	if room_id == "":
		print(
			"Submission: damaged Mage has no Room"
		)
		return false

	game.place_player_instability(
		caster_id,
		room_id,
		amount
	)

	print(
		"Submission: ",
		black_rose_damage,
		" Black Rose Damage on Player ",
		damaged_player_index + 1,
		" -> ",
		amount,
		" Instability in ",
		room_id
	)

	return true
func resolve_place_instability_per_self_black_rose_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var room_id = str(
		context.get("room_id", "")
	)

	if room_id == "":
		print(
			"Heart of Ice: target Room missing"
		)
		return false

	var mage = game.players[caster_id].mage

	var black_rose_damage = (
		mage.get_damage_from(-1)
	)

	var instability_per_damage = int(
		effect.get(
			"instability_per_damage",
			1
		)
	)

	var max_instability = int(
		effect.get("max", 4)
	)

	var amount = (
		black_rose_damage
		* instability_per_damage
	)

	amount = min(
		amount,
		max_instability
	)

	if amount <= 0:
		return true

	game.place_player_instability(
		caster_id,
		room_id,
		amount
	)

	print(
		"Heart of Ice: ",
		black_rose_damage,
		" Black Rose Damage -> ",
		amount,
		" Instability in ",
		room_id
	)

	return true

func resolve_damage_per_revealed_active_element(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false

	if target_player_index < 0 \
	or target_player_index >= game.players.size():
		return false

	var element = str(
		effect.get("element", "")
	)

	if element == "":
		return false

	var amount_per_element = int(
		effect.get(
			"amount_per_element",
			1
		)
	)

	var element_counts = (
		game.get_revealed_element_counts(
			caster_id
		)
	)

	var matching_elements = int(
		element_counts.get(
			element,
			0
		)
	)

	# "all" vale anche come elemento richiesto.
	matching_elements += int(
		element_counts.get(
			"all",
			0
		)
	)

	var amount = (
		matching_elements
		* amount_per_element
	)

	if amount <= 0:
		return true

	game.deal_damage(
		caster_id,
		target_player_index,
		amount,
		"spell"
	)

	print(
		"Element Damage: ",
		matching_elements,
		" ",
		element,
		" Revealed -> ",
		amount,
		" Damage"
	)

	return true
func resolve_modify_spell_target(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var new_target = str(
		effect.get("target", "")
	)

	if new_target == "":
		return false

	context["spell_target_type"] = new_target

	if effect.has("range"):
		context["spell_range"] = effect["range"]

	print(
		"Spell target changed to ",
		new_target,
		" | Range: ",
		context.get("spell_range", null)
	)

	return true
	
func resolve_move_one_model_damaged_by_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	# Nessun Model ha effettivamente subito Damage:
	# l'effetto non ha nulla da muovere.
	if damaged_models.is_empty():
		return true


	var selected_index = int(
		context.get(
			"damaged_model_to_move_index",
			-1
		)
	)

	var destination_room_id = str(
		context.get(
			"movement_destination_room_id",
			""
		)
	)


	# In futuro qui apriremo la UI di scelta.
	if selected_index < 0 \
	or selected_index >= damaged_models.size():

		print(
			"Deflagrate: damaged Model selection required"
		)

		return false


	if destination_room_id == "":
		print(
			"Deflagrate: movement destination required"
		)

		return false


	var model = damaged_models[
		selected_index
	]

	var model_type = str(
		model.get("type", "")
	)


	match model_type:

		"mage":
			var player_index = int(
				model.get(
					"player_index",
					-1
				)
			)

			return game.move_mage_to_room_id(
				player_index,
				destination_room_id,
				int(effect.get("distance", 1))
			)


		"evocation":
			var evocation = model.get(
				"evocation"
			)

			if evocation == null:
				return false

			return game.move_evocation_to_room_id(
				evocation,
				destination_room_id,
				int(effect.get("distance", 1))
			)


		_:
			return false

func register_damaged_model(
	context: Dictionary,
	model_data: Dictionary
):
	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	var model_type = str(
		model_data.get("type", "")
	)

	for existing in damaged_models:
		if str(existing.get("type", "")) != model_type:
			continue

		if model_type == "mage":
			if int(existing.get("player_index", -1)) == int(
				model_data.get("player_index", -1)
			):
				return

		elif model_type == "evocation":
			if existing.get("evocation") == model_data.get("evocation"):
				return

	damaged_models.append(model_data)

	context["models_damaged_by_effect"] = damaged_models

func resolve_place_instability_per_revealed_active_element(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false

	var caster_id = int(
		context.get("caster_id", -1)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false

	var element = str(
		effect.get("element", "")
	)

	if element == "":
		return false


	# =====================================================
	# CONTA GLI ELEMENTI SULLE REVEALED SPELL
	# =====================================================

	var element_counts = (
		game.get_revealed_element_counts(
			caster_id
		)
	)

	var matching_elements = int(
		element_counts.get(
			element,
			0
		)
	)

	# All Elements può essere considerato come
	# l'elemento richiesto.
	matching_elements += int(
		element_counts.get(
			"all",
			0
		)
	)

	var amount_per_element = int(
		effect.get(
			"amount_per_element",
			1
		)
	)

	var amount = (
		matching_elements
		* amount_per_element
	)

	if amount <= 0:
		return true


	# =====================================================
	# TROVA LA ROOM DEL MODEL TARGET
	# =====================================================

	var target_model_type = str(
		context.get(
			"target_model_type",
			""
		)
	)

	# Compatibilità con i test in cui un Model è
	# rappresentato direttamente da target_player_index.
	if target_model_type == "" \
	and context.has("target_player_index"):

		target_model_type = "mage"


	var room_id = ""


	match target_model_type:

		"mage":
			var target_player_index = int(
				context.get(
					"target_player_index",
					-1
				)
			)

			if target_player_index < 0 \
			or target_player_index >= game.players.size():
				return false

			room_id = (
				game.players[target_player_index]
				.mage
				.room_id
			)


		"evocation":
			var target_evocation = context.get(
				"target_evocation"
			)

			if target_evocation == null:
				return false

			room_id = target_evocation.room_id


		_:
			print(
				"Athanor Eruption: invalid target Model type: ",
				target_model_type
			)
			return false


	if room_id == "":
		print(
			"Athanor Eruption: target Model has no Room"
		)
		return false


	# =====================================================
	# PLACE INSTABILITY
	# =====================================================

	game.place_player_instability(
		caster_id,
		room_id,
		amount
	)

	print(
		"Athanor Eruption: ",
		matching_elements,
		" ",
		element,
		" Revealed -> ",
		amount,
		" Instability in ",
		room_id
	)

	return true

func resolve_damage_all_models_of_type(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-999
		)
	)

	var amount = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true


	var model_type = str(
		effect.get(
			"model_type",
			""
		)
	)


	if model_type != "mage" \
	and model_type != "evocation":

		print(
			"damage_all_models_of_type: ",
			"invalid model_type: ",
			model_type
		)

		return false


	# =====================================================
	# ALL ACTIVE MAGES
	#
	# Un Mage nella propria Cell è immune.
	# Quindi gli effetti globali non lo colpiscono.
	# =====================================================

	if model_type == "mage":

		var active_player_count = min(
			game.player_count,
			game.players.size()
		)


		for player_index in range(
			active_player_count
		):

			var mage = (
				game.players[player_index]
					.mage
			)


			# ---------------------------------------------
			# CELL IMMUNITY
			# ---------------------------------------------

			if game.is_mage_in_cell(
				player_index
			):
				continue


			# ---------------------------------------------
			# DAMAGE
			# ---------------------------------------------

			var damage_dealt = (
				game.deal_damage(
					caster_id,
					player_index,
					amount,
					"spell"
				)
			)


			# ---------------------------------------------
			# TRACKING
			#
			# Serve agli effetti successivi che fanno
			# riferimento ai Models danneggiati da questo
			# Effect.
			# ---------------------------------------------

			if damage_dealt > 0:

				register_damaged_model(
					context,
					{
						"type": "mage",
						"player_index":
							player_index,
						"room_id":
							mage.room_id
					}
				)


		return true


	# =====================================================
	# ALL ACTIVE EVOCATIONS
	#
	# Le Evocation non usano la regola di immunità delle
	# Cell dei Mage.
	#
	# Non usiamo is_lodge_room_id(), perché quello aveva
	# erroneamente escluso Evocation in Room valide come
	# "oracle".
	# =====================================================

	var active_player_count = min(
		game.player_count,
		game.players.size()
	)


	for player_index in range(
		active_player_count
	):

		var player = game.players[
			player_index
		]


		for evocation in player.evocations:

			var damage_dealt = (
				game.deal_damage_to_evocation(
					caster_id,
					evocation,
					amount
				)
			)


			if damage_dealt > 0:

				register_damaged_model(
					context,
					{
						"type":
							"evocation",
						"evocation":
							evocation,
						"room_id":
							evocation.room_id
					}
				)


	return true

func resolve_summon_same_evocation_as_trigger(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	# =====================================================
	# CASTER
	#
	# Il controller di Stone Phoenix è il giocatore
	# che deve evocare la nuova Evocation.
	# =====================================================

	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)


	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"summon_same_evocation_as_trigger: invalid caster"
		)

		return false


	# =====================================================
	# EVOCATION CHE HA GENERATO IL TRIGGER
	# =====================================================

	var trigger_evocation = context.get(
		"trigger_evocation"
	)


	if trigger_evocation == null:

		print(
			"summon_same_evocation_as_trigger: "
			+ "trigger Evocation missing"
		)

		return false


	# =====================================================
	# SAME TYPE
	#
	# Usiamo direttamente evocation_id.
	#
	# Esempio:
	# Succubus defeated -> summon Succubus
	# Nigredo removed   -> summon Nigredo
	# =====================================================

	var evocation_id = str(
		trigger_evocation.evocation_id
	)


	if evocation_id == "":

		print(
			"summon_same_evocation_as_trigger: "
			+ "trigger Evocation has no id"
		)

		return false


	# =====================================================
	# ROOM
	#
	# La nuova Evocation viene evocata nella Room
	# della Evocation sconfitta/rimossa.
	# =====================================================

	var room_id = str(
		context.get(
			"trigger_evocation_room_id",
			""
		)
	)


	if room_id == "":

		print(
			"summon_same_evocation_as_trigger: "
			+ "trigger Room missing"
		)

		return false


	# =====================================================
	# SUMMON
	# =====================================================

	var summoned_evocation = game.summon_evocation(
		caster_id,
		evocation_id,
		room_id
	)


	if summoned_evocation == null:

		print(
			"summon_same_evocation_as_trigger: "
			+ "failed to summon ",
			evocation_id
		)

		return false


	# =====================================================
	# STORE
	#
	# Il secondo Effect di Stone Phoenix Dark,
	# activate_summoned_evocation, usa questa variabile.
	# =====================================================

	context["last_summoned_evocation"] = (
		summoned_evocation
	)


	print(
		"Stone Phoenix: summoned same Evocation ",
		summoned_evocation.evocation_name,
		" in ",
		room_id
	)


	return true
func resolve_activate_room_from_owned_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"Soul Transfer: invalid caster"
		)

		return false


	# =====================================================
	# TARGET ROOM
	# =====================================================

	var target_room_id = str(
		context.get(
			"target_room_id",
			""
		)
	)

	if target_room_id == "":

		print(
			"Soul Transfer: target Room missing"
		)

		return false


	# =====================================================
	# EXCLUDED ROOMS
	# =====================================================

	var excluded_rooms: Array = effect.get(
		"excluded_rooms",
		[]
	)

	if target_room_id in excluded_rooms:

		print(
			"Soul Transfer: Room ",
			target_room_id,
			" is excluded"
		)

		return false


	# =====================================================
	# REQUIRED EVOCATION ARCHETYPE
	# =====================================================

	var required_archetype = str(
		effect.get(
			"evocation_archetype",
			""
		)
	)

	if required_archetype == "":

		print(
			"Soul Transfer: missing required archetype"
		)

		return false


	# =====================================================
	# FIND OWNED CONSTRUCT IN TARGET ROOM
	# =====================================================

	var valid_evocation = null

	for evocation in game.players[
		caster_id
	].evocations:

		if evocation == null:
			continue

		if evocation.is_defeated():
			continue

		if str(
			evocation.archetype
		) != required_archetype:
			continue

		if evocation.room_id != target_room_id:
			continue

		valid_evocation = evocation
		break


	if valid_evocation == null:

		print(
			"Soul Transfer: no owned ",
			required_archetype,
			" in ",
			target_room_id
		)

		return false


	# =====================================================
	# ACTIVATE ROOM
	#
	# true = ignora il limite di una Room flipped
	# già attivata questo turno.
	# =====================================================

	var success = game.activate_room(
		caster_id,
		target_room_id,
		true
	)

	if not success:

		print(
			"Soul Transfer: Room activation failed"
		)

		return false


	print(
		"Soul Transfer: ",
		valid_evocation.evocation_name,
		" activated Room ",
		target_room_id
	)

	return true
func resolve_remove_owned_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"Soul Transfer: invalid caster"
		)

		return false


	var required_archetype = str(
		effect.get(
			"evocation_archetype",
			""
		)
	)


	# =====================================================
	# EVOCATION CHOSEN BY THE PLAYER
	#
	# Per ora arriva dal context.
	# Più avanti sarà scelta dalla UI.
	# =====================================================

	var target_evocation = context.get(
		"target_evocation"
	)


	if target_evocation == null:

		print(
			"Soul Transfer: no Evocation selected for removal"
		)

		return false


	# =====================================================
	# MUST BE OWNED BY CASTER
	# =====================================================

	if target_evocation.owner_id != caster_id:

		print(
			"Soul Transfer: selected Evocation is not owned by caster"
		)

		return false


	# =====================================================
	# MUST BE A CONSTRUCT
	# =====================================================

	if required_archetype != "" \
	and str(
		target_evocation.archetype
	) != required_archetype:

		print(
			"Soul Transfer: selected Evocation is not a ",
			required_archetype
		)

		return false


	# =====================================================
	# FIND IN PLAYER EVOCATIONS
	# =====================================================

	var player = game.players[caster_id]

	var index = player.evocations.find(
		target_evocation
	)


	if index == -1:

		print(
			"Soul Transfer: Evocation not found in owner's list"
		)

		return false


	# =====================================================
	# SAVE DATA BEFORE REMOVAL
	# =====================================================

	var removed_room_id = str(
		target_evocation.room_id
	)


	# =====================================================
	# IMPORTANT:
	# emit event BEFORE removing object from player's list
	#
	# Stone Phoenix may need:
	# - evocation id
	# - archetype
	# - room
	# - owner
	# =====================================================

	game.emit_evocation_defeated_or_removed(
		target_evocation,
		"removed"
	)


	# =====================================================
	# REMOVE FROM PLAY
	# =====================================================

	player.evocations.remove_at(
		index
	)


	# =====================================================
	# STORE RESULT FOR FOLLOWING EFFECT
	# =====================================================

	context["removed_evocation"] = (
		target_evocation
	)

	context["removed_evocation_room_id"] = (
		removed_room_id
	)

	context["removed_evocation_success"] = true


	print(
		"Soul Transfer: removed ",
		target_evocation.evocation_name,
		" from ",
		removed_room_id
	)


	return true
	
func resolve_summon_evocation_from_deck(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false


	# =====================================================
	# "IF YOU DO"
	# =====================================================

	if not bool(
		context.get(
			"removed_evocation_success",
			false
		)
	):

		print(
			"Soul Transfer: no Construct was removed"
		)

		return false


	var max_health = int(
		effect.get(
			"max_health",
			3
		)
	)


	# =====================================================
	# TEMPORARY SELECTION INPUT
	#
	# Finché non costruiamo il vero Evocation Deck,
	# il test può passare l'id scelto nel context.
	# =====================================================

	var chosen_evocation_id = str(
		context.get(
			"chosen_evocation_id",
			""
		)
	)


	if chosen_evocation_id == "":

		print(
			"Soul Transfer: no Evocation chosen from deck"
		)

		return false


	var data = game.evocation_database.get_evocation(
		chosen_evocation_id
	)


	if data.is_empty():

		print(
			"Soul Transfer: unknown Evocation ",
			chosen_evocation_id
		)
		return false
	if game.get_available_evocation_copies(
	chosen_evocation_id
		) <= 0:

		print(
			"Soul Transfer: ",
			chosen_evocation_id,
			" is not available in the Evocation Deck"
		)

		return false


	var health = int(
		data.get(
			"health",
			999
		)
	)


	if health > max_health:

		print(
			"Soul Transfer: ",
			data.get(
				"name",
				chosen_evocation_id
			),
			" has Health ",
			health,
			" > ",
			max_health
		)

		return false


	# =====================================================
	# SUMMON ROOM
	# =====================================================

	var room_id = str(
		context.get(
			"target_room_id",
			""
		)
	)


	if room_id == "":

		print(
			"Soul Transfer: summon Room missing"
		)

		return false


	var summoned = game.summon_evocation(
		caster_id,
		chosen_evocation_id,
		room_id
	)


	if summoned == null:

		print(
			"Soul Transfer: summon failed"
		)

		return false


	context["last_summoned_evocation"] = (
		summoned
	)


	print(
		"Soul Transfer: summoned ",
		summoned.evocation_name,
		" from Evocation Deck"
	)


	return true

func resolve_remove_owned_evocation_and_damage_around(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"Liquid Fire: invalid caster"
		)

		return false


	# =====================================================
	# EVOCATION CHOSEN FOR REMOVAL
	# =====================================================

	var target_evocation = context.get(
		"target_evocation"
	)

	if target_evocation == null:

		print(
			"Liquid Fire: no Evocation selected"
		)

		return false


	if target_evocation.owner_id != caster_id:

		print(
			"Liquid Fire: selected Evocation is not owned by caster"
		)

		return false


	var player = game.players[caster_id]

	var index = player.evocations.find(
		target_evocation
	)

	if index == -1:

		print(
			"Liquid Fire: selected Evocation is not in play"
		)

		return false


	# =====================================================
	# SAVE ORIGIN BEFORE REMOVAL
	# =====================================================

	var origin_room_id = str(
		target_evocation.room_id
	)

	var origin_coord = game.room_id_to_coord(
		origin_room_id
	)


	var damage = int(
		effect.get(
			"damage",
			2
		)
	)

	var distance = int(
		effect.get(
			"distance",
			1
		)
	)


	# =====================================================
	# REMOVE EVOCATION
	#
	# Event is emitted before removing it from player's list
	# so Stone Phoenix and similar effects can react.
	# =====================================================

	game.emit_evocation_defeated_or_removed(
		target_evocation,
		"removed"
	)

	player.evocations.remove_at(
		index
	)


	print(
		"Liquid Fire: removed ",
		target_evocation.evocation_name,
		" from ",
		origin_room_id
	)


	# =====================================================
	# DAMAGE ALL MAGES AT EXACT DISTANCE
	# =====================================================

	for target_player_index in range(
		game.players.size()
	):

		var mage = game.players[
			target_player_index
		].mage

		if mage.in_cell:
			continue

		var target_coord = game.room_id_to_coord(
			mage.room_id
		)

		if game.get_hex_distance(
			origin_coord,
			target_coord
		) > distance:
			continue


		var damage_dealt = game.deal_damage(
			caster_id,
			target_player_index,
			damage,
			"spell"
		)


		if damage_dealt > 0:

			var damaged_models: Array = context.get(
				"models_damaged_by_effect",
				[]
			)

			damaged_models.append(
				{
					"type": "mage",
					"player_index": target_player_index
				}
			)

			context[
				"models_damaged_by_effect"
			] = damaged_models


	# =====================================================
	# DAMAGE ALL EVOCATIONS AT EXACT DISTANCE
	# =====================================================

	for target_player in game.players:

		# Copy because damage can defeat/remove an Evocation
		var evocations_snapshot = (
			target_player.evocations.duplicate()
		)

		for evocation in evocations_snapshot:

			if evocation == null:
				continue

			if evocation.is_defeated():
				continue

			var target_coord = game.room_id_to_coord(
				evocation.room_id
			)

			if game.get_hex_distance(
				origin_coord,
				target_coord
			) > distance:
				continue


			var damage_dealt = (
				game.deal_damage_to_evocation(
					caster_id,
					evocation,
					damage
				)
			)


			if damage_dealt > 0:

				var damaged_models: Array = context.get(
					"models_damaged_by_effect",
					[]
				)

				damaged_models.append(
					{
						"type": "evocation",
						"evocation": evocation
					}
				)

				context[
					"models_damaged_by_effect"
				] = damaged_models


	return true
func resolve_damage_models_damaged_by_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"damage_models_damaged_by_effect: invalid caster"
		)

		return false


	var amount = int(
		effect.get(
			"amount",
			1
		)
	)

	if amount <= 0:
		return true


	# =====================================================
	# MODELS DAMAGED BY THE BASE EFFECT
	#
	# Facciamo una copia perché il nuovo Damage potrebbe
	# sconfiggere Evocation e generare altri eventi.
	# =====================================================

	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	).duplicate()


	if damaged_models.is_empty():

		print(
			"Liquid Fire Enhancement: no damaged Models"
		)

		return true


	print(
		"Liquid Fire Enhancement: damaging ",
		damaged_models.size(),
		" Models for ",
		amount,
		" additional Damage"
	)


	# =====================================================
	# IMPORTANT
	#
	# NON registriamo nuovamente questi Damage dentro
	# models_damaged_by_effect.
	#
	# Quella lista rappresenta i Models che hanno subito
	# Damage dall'Effect base e determina i bersagli
	# dell'Enhancement.
	# =====================================================

	for model in damaged_models:

		var model_type = str(
			model.get(
				"type",
				""
			)
		)


		match model_type:

			"mage":

				var player_index = int(
					model.get(
						"player_index",
						-1
					)
				)

				if player_index < 0 \
				or player_index >= game.players.size():
					continue


				game.deal_damage(
					caster_id,
					player_index,
					amount,
					"spell"
				)


			"evocation":

				var evocation = model.get(
					"evocation"
				)

				if evocation == null:
					continue


				# Potrebbe essere stata sconfitta/rimossa
				# da un trigger generato dal primo Damage.
				var still_in_play = false

				for player in game.players:

					if player.evocations.has(
						evocation
					):

						still_in_play = true
						break


				if not still_in_play:
					continue


				if evocation.is_defeated():
					continue


				game.deal_damage_to_evocation(
					caster_id,
					evocation,
					amount
				)


			_:

				print(
					"Liquid Fire Enhancement: "
					+ "unknown damaged Model type: ",
					model_type
				)


	return true

func resolve_activate_owned_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"activate_owned_evocation: invalid caster"
		)

		return false


	# =====================================================
	# REQUIRED ARCHETYPE
	# =====================================================

	var required_archetype = str(
		effect.get(
			"evocation_archetype",
			""
		)
	)


	# =====================================================
	# CHOOSE EVOCATION
	#
	# Temporary:
	# - if context contains selected_evocation_to_activate,
	#   use it;
	# - otherwise automatically use the first valid one.
	#
	# Later this becomes a UI choice.
	# =====================================================

	var selected_evocation = context.get(
		"selected_evocation_to_activate"
	)


	if selected_evocation != null:

		if selected_evocation.owner_id != caster_id:

			print(
				"Liquid Fire Enhancement: "
				+ "selected Evocation is not owned by caster"
			)

			return false


		if selected_evocation.is_defeated():

			print(
				"Liquid Fire Enhancement: "
				+ "selected Evocation is defeated"
			)

			return false


		if required_archetype != "" \
		and str(
			selected_evocation.archetype
		) != required_archetype:

			print(
				"Liquid Fire Enhancement: "
				+ "selected Evocation is not a ",
				required_archetype
			)

			return false


	else:

		for evocation in game.players[
			caster_id
		].evocations:

			if evocation == null:
				continue

			if evocation.is_defeated():
				continue

			if required_archetype != "" \
			and str(
				evocation.archetype
			) != required_archetype:
				continue

			selected_evocation = evocation
			break


	# =====================================================
	# NO VALID CONSTRUCT
	#
	# Non consideriamo questo un errore di risoluzione
	# della Spell: semplicemente non c'è un Construct
	# che possa beneficiare dell'Enhancement.
	# =====================================================

	if selected_evocation == null:

		print(
			"Liquid Fire Enhancement: "
			+ "no valid ",
			required_archetype,
			" to activate"
		)

		return true


	# =====================================================
	# TEMPORARY ACTIVATION BONUS
	#
	# NON modifichiamo selected_evocation.strength.
	#
	# Il bonus appartiene esclusivamente a questa
	# attivazione.
	# =====================================================

	var strength_bonus = int(
		effect.get(
			"strength_bonus",
			0
		)
	)

	var activation_strength = (
		selected_evocation.strength
		+ strength_bonus
	)


	context[
		"last_activated_evocation"
	] = selected_evocation

	context[
		"last_evocation_activation_strength"
	] = activation_strength

	context[
		"last_evocation_activation_strength_bonus"
	] = strength_bonus


	# =====================================================
	# ACTIVATION PLACEHOLDER
	# =====================================================

	print(
		"Liquid Fire Enhancement: ",
		selected_evocation.evocation_name,
		" activates"
	)

	print(
		"Activation Strength: ",
		selected_evocation.strength,
		" + ",
		strength_bonus,
		" = ",
		activation_strength
	)


	return true
func resolve_remove_evocation_with_max_health(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var target_evocation = context.get(
		"target_evocation"
	)

	if target_evocation == null:

		print(
			"Fountain of the Three: "
			+ "target Evocation missing"
		)

		return false


	# =====================================================
	# HEALTH LIMIT
	# =====================================================

	var max_health = int(
		effect.get(
			"max_health",
			3
		)
	)


	if target_evocation.health > max_health:

		print(
			"Fountain of the Three: ",
			target_evocation.evocation_name,
			" has Health ",
			target_evocation.health,
			" > ",
			max_health
		)

		return false


	# =====================================================
	# CHECK OWNER / IN PLAY
	# =====================================================

	var owner_id = target_evocation.owner_id

	if owner_id < 0 \
	or owner_id >= game.players.size():

		print(
			"Fountain of the Three: "
			+ "invalid Evocation owner"
		)

		return false


	var owner_player = game.players[
		owner_id
	]

	var index = owner_player.evocations.find(
		target_evocation
	)


	if index == -1:

		print(
			"Fountain of the Three: "
			+ "target Evocation is not in play"
		)

		return false


	# =====================================================
	# SAVE DATA BEFORE REMOVAL
	# =====================================================

	var removed_room_id = str(
		target_evocation.room_id
	)


	# =====================================================
	# EVENT BEFORE REMOVAL
	#
	# Stone Phoenix e altri trigger devono poter reagire
	# alla rimozione.
	# =====================================================

	game.emit_evocation_defeated_or_removed(
		target_evocation,
		"removed"
	)


	# =====================================================
	# REMOVE
	# =====================================================

	owner_player.evocations.remove_at(
		index
	)


	# =====================================================
	# STORE RESULT
	# =====================================================

	context[
		"removed_evocation"
	] = target_evocation

	context[
		"removed_evocation_room_id"
	] = removed_room_id

	context[
		"removed_evocation_success"
	] = true


	print(
		"Fountain of the Three: removed ",
		target_evocation.evocation_name,
		" from ",
		removed_room_id
	)


	return true
	
func resolve_summon_evocation_at_removed_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"Fountain of the Three: invalid caster"
		)

		return false


	# =====================================================
	# "IF YOU DO"
	# =====================================================

	if not bool(
		context.get(
			"removed_evocation_success",
			false
		)
	):

		print(
			"Fountain of the Three: "
			+ "no Evocation was removed"
		)

		return false


	# =====================================================
	# EVOCATION TO SUMMON
	# =====================================================

	var evocation_id = str(
		effect.get(
			"evocation_id",
			""
		)
	)

	if evocation_id == "":

		print(
			"Fountain of the Three: "
			+ "missing evocation_id"
		)

		return false


	# =====================================================
	# ROOM OF REMOVED EVOCATION
	# =====================================================

	var room_id = str(
		context.get(
			"removed_evocation_room_id",
			""
		)
	)

	if room_id == "":

		print(
			"Fountain of the Three: "
			+ "removed Evocation Room missing"
		)

		return false


	# =====================================================
	# SUMMON
	# =====================================================

	var summoned = game.summon_evocation(
		caster_id,
		evocation_id,
		room_id
	)

	if summoned == null:

		print(
			"Fountain of the Three: "
			+ "failed to summon ",
			evocation_id
		)

		return false


	context[
		"last_summoned_evocation"
	] = summoned


	print(
		"Fountain of the Three: summoned ",
		summoned.evocation_name,
		" in ",
		room_id
	)


	return true
func resolve_fountain_construct_or_nigredo(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():

		print(
			"Fountain of the Three Dark: invalid caster"
		)

		return false


	var target_room_id = str(
		context.get(
			"target_room_id",
			""
		)
	)

	if target_room_id == "":

		print(
			"Fountain of the Three Dark: target Room missing"
		)

		return false


	# =====================================================
	# PLAYER CHOICE
	#
	# Temporary context interface:
	#
	# "fountain_choice": "activate_construct"
	#
	# or
	#
	# "fountain_choice": "summon_nigredo"
	#
	# Più avanti sarà una scelta UI.
	# =====================================================

	var choice = str(
		context.get(
			"fountain_choice",
			""
		)
	)


	# =====================================================
	# OPTION 1:
	# A CONSTRUCT IN TARGET ROOM ACTIVATES
	# UNDER YOUR CONTROL
	# =====================================================

	if choice == "activate_construct":

		var selected_construct = context.get(
			"selected_evocation_to_activate"
		)


		# -------------------------------------------------
		# If one was explicitly selected, validate it.
		# -------------------------------------------------

		if selected_construct != null:

			if selected_construct.is_defeated():

				print(
					"Fountain of the Three Dark: "
					+ "selected Construct is defeated"
				)

				return false


			if str(
				selected_construct.archetype
			) != "construct":

				print(
					"Fountain of the Three Dark: "
					+ "selected Evocation is not a Construct"
				)

				return false


			if selected_construct.room_id != target_room_id:

				print(
					"Fountain of the Three Dark: "
					+ "selected Construct is not in target Room"
				)

				return false


			var found_in_play = false

			for player in game.players:

				if player.evocations.has(
					selected_construct
				):

					found_in_play = true
					break


			if not found_in_play:

				print(
					"Fountain of the Three Dark: "
					+ "selected Construct is not in play"
				)

				return false


		# -------------------------------------------------
		# Temporary automatic selection.
		# First valid Construct in target Room.
		# -------------------------------------------------

		else:

			for player in game.players:

				for evocation in player.evocations:

					if evocation == null:
						continue

					if evocation.is_defeated():
						continue

					if str(
						evocation.archetype
					) != "construct":
						continue

					if evocation.room_id != target_room_id:
						continue

					selected_construct = evocation
					break


				if selected_construct != null:
					break


		if selected_construct == null:

			print(
				"Fountain of the Three Dark: "
				+ "no Construct in target Room"
			)

			return false


		# =================================================
		# ACTIVATION PLACEHOLDER
		#
		# IMPORTANT:
		# owner_id DOES NOT CHANGE.
		#
		# We only record that this activation is controlled
		# by the caster.
		# =================================================

		context[
			"last_activated_evocation"
		] = selected_construct

		context[
			"last_evocation_activation_controller"
		] = caster_id


		print(
			"Fountain of the Three Dark: ",
			selected_construct.evocation_name,
			" activates under Player ",
			caster_id + 1,
			"'s control"
		)


		return true


	# =====================================================
	# OPTION 2:
	# SUMMON A NIGREDO
	# =====================================================

	if choice == "summon_nigredo":

		var summoned = game.summon_evocation(
			caster_id,
			"nigredo",
			target_room_id
		)


		if summoned == null:

			print(
				"Fountain of the Three Dark: "
				+ "failed to summon Nigredo"
			)

			return false


		context[
			"last_summoned_evocation"
		] = summoned


		print(
			"Fountain of the Three Dark: "
			+ "summoned Nigredo in ",
			target_room_id
		)


		return true


	# =====================================================
	# NO CHOICE
	# =====================================================

	print(
		"Fountain of the Three Dark: "
		+ "choice required"
	)

	return false
func resolve_heal_target_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	var target_evocation = context.get(
		"target_evocation"
	)


	if target_evocation == null:

		print(
			"Purifying Aludel: target Evocation missing"
		)

		return false


	# =====================================================
	# MUST BE YOUR EVOCATION
	# =====================================================

	var required_owner = str(
		effect.get(
			"owner",
			""
		)
	)


	if required_owner == "caster" \
	and target_evocation.owner_id != caster_id:

		print(
			"Purifying Aludel: target Evocation "
			+ "does not belong to caster"
		)

		return false


	if target_evocation.is_defeated():

		print(
			"Purifying Aludel: target Evocation "
			+ "is already defeated"
		)

		return false


	# =====================================================
	# REMOVE DAMAGE CUBES
	# =====================================================

	var amount = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true


	var healed = min(
		amount,
		target_evocation.damage_cubes.size()
	)


	for i in range(healed):

		var cube_owner = target_evocation.damage_cubes.pop_back()

		# Return cube to its actual owner.
		if cube_owner == -1:

			game.return_black_rose_cubes(
				1
			)

		elif cube_owner >= 0 \
		and cube_owner < game.players.size():

			game.return_owner_cubes(
				cube_owner,
				1
			)


	print(
		"Purifying Aludel: healed ",
		healed,
		" Damage from ",
		target_evocation.evocation_name,
		" | HP: ",
		target_evocation.get_remaining_health(),
		"/",
		target_evocation.health
	)


	return true

func resolve_next_activation_strength_bonus(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var target_evocation = context.get(
		"target_evocation"
	)

	if target_evocation == null:
		return false


	var amount = int(
		effect.get(
			"amount",
			0
		)
	)


	context[
		"pending_evocation_activation_strength_bonus"
	] = amount


	print(
		"Purifying Aludel: ",
		target_evocation.evocation_name,
		" gets Strength +",
		amount,
		" on its next activation"
	)


	return true

func resolve_activate_target_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var target_evocation = context.get(
		"target_evocation"
	)

	if target_evocation == null:
		return false


	if target_evocation.is_defeated():
		return false


	var strength_bonus = int(
		context.get(
			"pending_evocation_activation_strength_bonus",
			0
		)
	)


	var activation_strength = (
		target_evocation.strength
		+ strength_bonus
	)


	# =====================================================
	# ACTIVATION PLACEHOLDER
	# =====================================================

	context[
		"last_activated_evocation"
	] = target_evocation

	context[
		"last_evocation_activation_controller"
	] = target_evocation.owner_id

	context[
		"last_evocation_activation_strength"
	] = activation_strength

	context[
		"last_evocation_activation_strength_bonus"
	] = strength_bonus


	# Bonus consumed.
	context[
		"pending_evocation_activation_strength_bonus"
	] = 0


	print(
		"Evocation activation placeholder: ",
		target_evocation.evocation_name,
		" | controller P",
		target_evocation.owner_id + 1,
		" | Strength ",
		activation_strength,
		" (",
		target_evocation.strength,
		" + ",
		strength_bonus,
		")"
	)


	return true
	
func resolve_activate_target_evocation_under_control(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	var target_evocation = context.get(
		"target_evocation"
	)


	if target_evocation == null:

		print(
			"Purifying Aludel Dark: "
			+ "target Evocation missing"
		)

		return false


	if target_evocation.is_defeated():

		print(
			"Purifying Aludel Dark: "
			+ "target Evocation is defeated"
		)

		return false


	# =====================================================
	# ACTIVATION PLACEHOLDER
	#
	# The Evocation does NOT change owner.
	# Only this activation is controlled by caster.
	# =====================================================

	context[
		"last_activated_evocation"
	] = target_evocation

	context[
		"last_evocation_activation_controller"
	] = caster_id

	context[
		"last_evocation_activation_strength"
	] = target_evocation.strength

	context[
		"last_evocation_activation_strength_bonus"
	] = 0


	print(
		"Purifying Aludel Dark: ",
		target_evocation.evocation_name,
		" activates under P",
		caster_id + 1,
		"'s control",
		" | Strength ",
		target_evocation.strength
	)


	return true

func convert_damage_cubes(
	damage_cubes: Array,
	new_owner_id: int,
	amount: int
) -> int:

	var converted = 0


	for i in range(
		damage_cubes.size()
	):

		if converted >= amount:
			break


		var current_owner_id = int(
			damage_cubes[i]
		)


		# Already belongs to caster.
		if current_owner_id == new_owner_id:
			continue


		damage_cubes[i] = new_owner_id

		converted += 1


	return converted
	
func resolve_ignore_trigger_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var event = context.get(
		"trigger_event"
	)

	if event == null:

		print(
			"Silver of the Sages: trigger event missing"
		)

		return false


	var ignore_amount = int(
		effect.get(
			"amount",
			0
		)
	)

	if ignore_amount <= 0:
		return true


	var original_amount = event.amount

	var ignored = min(
		ignore_amount,
		original_amount
	)


	event.amount = max(
		0,
		original_amount - ignored
	)


	context[
		"silver_damage_ignored"
	] = ignored


	print(
		"Silver of the Sages: ignored ",
		ignored,
		" Damage",
		" | ",
		original_amount,
		" -> ",
		event.amount
	)


	return true

func resolve_activate_owned_evocation_then_black_rose_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false


	var selected_evocation = context.get(
		"selected_evocation_to_activate"
	)


	# =====================================================
	# IF TEST/UI DID NOT SELECT ONE,
	# PICK FIRST VALID OWN EVOCATION
	# =====================================================

	if selected_evocation == null:

		for evocation in game.players[
			caster_id
		].evocations:

			if evocation == null:
				continue

			if evocation.is_defeated():
				continue

			selected_evocation = evocation
			break


	if selected_evocation == null:

		print(
			"Silver of the Sages: "
			+ "no Evocation available to activate"
		)

		return false


	# Must belong to caster.
	if selected_evocation.owner_id != caster_id:

		print(
			"Silver of the Sages: "
			+ "selected Evocation is not yours"
		)

		return false


	if selected_evocation.is_defeated():
		return false


	# =====================================================
	# ACTIVATION PLACEHOLDER
	# =====================================================

	context[
		"last_activated_evocation"
	] = selected_evocation

	context[
		"last_evocation_activation_controller"
	] = caster_id

	context[
		"last_evocation_activation_strength"
	] = selected_evocation.strength


	print(
		"Silver of the Sages: ",
		selected_evocation.evocation_name,
		" activates",
		" | Strength ",
		selected_evocation.strength
	)


	# =====================================================
	# AFTER ACTIVATION:
	# BLACK ROSE INFLICTS DAMAGE
	# =====================================================

	var damage_amount = int(
		effect.get(
			"amount",
			1
		)
	)


	game.deal_damage_to_evocation(
		-1,
		selected_evocation,
		damage_amount
	)


	print(
		"Silver of the Sages: Black Rose inflicts ",
		damage_amount,
		" Damage to ",
		selected_evocation.evocation_name
	)


	return true
	
func resolve_silver_defeat_choice(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	if game == null:
		return false


	var caster_id = int(
		context.get(
			"caster_id",
			-1
		)
	)

	if caster_id < 0 \
	or caster_id >= game.players.size():
		return false


	var choice = str(
		context.get(
			"silver_choice",
			""
		)
	)


	# =====================================================
	# OPTION 1 — SUMMON NIGREDO
	# =====================================================

	if choice == "summon_nigredo":

		var room_id = str(
			context.get(
				"trigger_evocation_room_id",
				""
			)
		)


		# Defeat event is on Mage, so normally use
		# caster Mage's current Lodge Room.
		if room_id == "":

			room_id = game.players[
				caster_id
			].mage.room_id


		var summoned = game.summon_evocation(
			caster_id,
			"nigredo",
			room_id
		)


		if summoned == null:

			print(
				"Silver of the Sages: "
				+ "could not summon Nigredo"
			)

			return false


		context[
			"last_summoned_evocation"
		] = summoned


		print(
			"Silver of the Sages: summoned Nigredo in ",
			room_id
		)


		return true


	# =====================================================
	# OPTION 2 — ACTIVATE ONE OF YOUR CONSTRUCTS
	# =====================================================

	if choice == "activate_construct":

		var selected_construct = context.get(
			"selected_evocation_to_activate"
		)


		if selected_construct == null:

			for evocation in game.players[
				caster_id
			].evocations:

				if evocation == null:
					continue

				if evocation.is_defeated():
					continue

				if evocation.archetype != "construct":
					continue

				selected_construct = evocation
				break


		if selected_construct == null:

			print(
				"Silver of the Sages: "
				+ "no Construct available"
			)

			return false


		if selected_construct.owner_id != caster_id:
			return false


		if selected_construct.archetype != "construct":
			return false


		context[
			"last_activated_evocation"
		] = selected_construct

		context[
			"last_evocation_activation_controller"
		] = caster_id

		context[
			"last_evocation_activation_strength"
		] = selected_construct.strength


		print(
			"Silver of the Sages: ",
			selected_construct.evocation_name,
			" activates",
			" | Strength ",
			selected_construct.strength
		)


		return true


	print(
		"Silver of the Sages: choice required"
	)

	return false
