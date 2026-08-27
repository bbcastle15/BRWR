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
		_:
			print("UNKNOWN EFFECT TYPE: ", effect_type)
			return false

func resolve_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(
		context.get("caster_id", -999)
	)

	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var amount = int(
		effect.get("amount", 0)
	)

	if game == null:
		return false

	if target_player_index < 0 \
	or target_player_index >= game.players.size():
		return false

	var damage_dealt = game.deal_damage(
		caster_id,
		target_player_index,
		amount,
		"spell"
	)

	# =====================================================
	# RISULTATO DELL'ULTIMO DAMAGE
	#
	# Serve per effetti concatenati come:
	# - Visceral Fire
	# - Submission
	# - future condizioni basate sul Damage appena inflitto
	# =====================================================

	context["last_damage_dealt"] = damage_dealt

	context["last_damage_target_player_index"] = (
		target_player_index
	)

	context["last_damage_defeated_target"] = (
		game.players[target_player_index]
		.mage
		.is_defeated()
	)


	# =====================================================
	# MODELLO EFFETTIVAMENTE DANNEGGIATO
	#
	# Lo registriamo solo se è stato realmente inflitto
	# almeno 1 Damage.
	# =====================================================

	if damage_dealt > 0:
		context["last_damaged_model_type"] = "mage"

		context["last_damaged_player_index"] = (
			target_player_index
		)

	return true
	
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
	var caster_id = int(context.get("caster_id", -999))
	var room_id = str(context.get("room_id", ""))

	var amount = int(effect.get("amount", 1))

	if game == null:
		return false

	if room_id == "":
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
	var caster_id = int(context.get("caster_id", -1))
	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	if target_player_index < 0 or target_player_index >= game.players.size():
		return false

	if amount <= 0:
		return true

	var target_mage = game.players[target_player_index].mage
	var converted = 0

	for i in range(target_mage.damage_cubes.size()):
		if converted >= amount:
			break

		var owner_id = target_mage.damage_cubes[i]

		if owner_id == caster_id:
			continue

		target_mage.damage_cubes[i] = caster_id
		converted += 1

	if target_player_index < game.player_boards.size():
		game.player_boards[target_player_index].refresh()

	print(
		"Convert damage: Player ",
		caster_id + 1,
		" converted ",
		converted,
		" damage on Player ",
		target_player_index + 1
	)

	return true

func resolve_summon_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")

	var caster_id = int(
		context.get("caster_id", -1)
	)

	var room_id = str(
		context.get("caster_room_id", "")
	)

	var evocation_id = str(
		effect.get("evocation_id", "")
	)

	if game == null:
		return false

	if caster_id < 0:
		return false

	if evocation_id == "":
		return false

	if room_id == "":
		print("Summon failed: caster_room_id missing")
		return false

	var summoned = game.summon_evocation(
		caster_id,
		evocation_id,
		room_id
	)

	if summoned == null:
		return false

	# Ci servirà immediatamente per:
	# "It activates."
	context["last_summoned_evocation"] = summoned

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
	var caster_id = int(context.get("caster_id", -1))

	var target_evocation = context.get(
		"target_evocation"
	)

	if game == null:
		return false

	if target_evocation == null:
		return false

	if caster_id < 0 or caster_id >= game.players.size():
		return false

	var player = game.players[caster_id]

	var index = player.evocations.find(
		target_evocation
	)

	if index == -1:
		print("Target Evocation not owned by caster")
		return false

	player.evocations.remove_at(index)

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
