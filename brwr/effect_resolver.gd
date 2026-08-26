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
		_:
			print("UNKNOWN EFFECT TYPE: ", effect_type)
			return false

func resolve_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = context.get("game")
	var caster_id = int(context.get("caster_id", -999))
	var target_player_index = int(
		context.get("target_player_index", -1)
	)

	var amount = int(effect.get("amount", 0))

	if game == null:
		return false

	if target_player_index < 0:
		return false

	game.deal_damage(
		caster_id,
		target_player_index,
		amount
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
