class_name EventEffectResolver
extends RefCounted

# These effects are consumed by Game callbacks while the card is on the board.
const PASSIVE_EFFECTS := [
	"mage_enters_cell_gain_power", "on_activate_room_color_black_rose_gain_power",
	"on_evocation_removed_black_rose_instability", "on_mage_places_instability_black_rose_instability",
	"on_spell_types_resolved_black_rose_damage", "combat_spell_damage_bonus",
	"on_quest_resolved_mage_and_black_rose_gain_power", "evocations_damage_immunity",
	"black_rose_claims_defeated_mage_trophies"
]

func resolve_event(event: EventCardState, context: Dictionary) -> bool:
	if event == null or context.get("game") == null:
		return false
	return context.game.queue_resolution({"type": "event_sequence", "event": event, "context": context})

func process_sequence(frame: Dictionary, game) -> bool:
	var event: EventCardState = frame.event
	var index: int = int(frame.get("index", 0))
	if index < event.effects.size():
		frame["index"] = index + 1
		resolve_effect(event.effects[index], frame.context)
		return false
	if not bool(frame.get("finalized", false)):
		frame["finalized"] = true
		if bool(frame.get("discard_after", false)):
			game.discard_event(event, true)
		game.refresh_all_player_boards()
		game.refresh_model_tokens()
	return true

func resolve_effect(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	if game == null:
		return false
	var kind: String = str(effect.get("type", ""))
	if kind in PASSIVE_EFFECTS:
		return true
	if kind == "each_mage_optional_black_rose_damage_then_activate_evocation":
		return game.queue_resolution({"type": "event_tribute", "order": _play_order(context), "damage": int(effect.get("damage", 1))})
	return game.queue_resolution({"type": "event_effect", "effect": effect, "context": context,
		"order": _play_order(context)})

# One step per target: damage/trigger frames and decisions finish before advancing.
func process_effect(frame: Dictionary, game) -> bool:
	var effect: Dictionary = frame.effect
	var kind: String = str(effect.get("type", ""))
	var context: Dictionary = frame.context
	var order: Array = frame.order
	var cursor: int = int(frame.get("cursor", 0))
	var amount: int = int(effect.get("amount", 1))
	if not frame.has("targets"):
		var targets: Array = order.duplicate()
		match kind:
			"black_rose_instability":
				targets = [str(effect.get("room_id", ""))]
			"black_rose_instability_room_colors":
				targets = []
				for room_id in game.room_id_by_coord.values():
					var room = game.get_room_by_id(room_id)
					if room != null and room.room_data.get("color", "") in effect.get("colors", []):
						targets.append(room_id)
			"black_rose_instability_each_room_with_mage":
				targets = []
				for p in game.players:
					if not p.mage.in_cell and not p.mage.room_id in targets:
						targets.append(p.mage.room_id)
			"black_rose_damage_all_evocations", "heal_all_evocations":
				targets = []
				for p in game.players:
					targets.append_array(p.evocations)
			"crown_owner_gain_power":
				targets = [game.crown_owner_id]
			"draw_event_from_moon":
				targets = range(amount)
		frame["targets"] = targets
	var targets: Array = frame.targets
	if cursor >= targets.size():
		# These cards explicitly perform the first sentence for all Mages first.
		if kind in ["black_rose_convert_damage_all_mages_then_damage_if_none", "heal_non_black_rose_damage_then_damage_mages_without_black_rose_damage"] and not bool(frame.get("damage_stage", false)):
			frame["damage_stage"] = true
			frame["cursor"] = 0
			return false
		return true
	var target = targets[cursor]
	match kind:
		"black_rose_instability", "black_rose_instability_room_colors", "black_rose_instability_each_room_with_mage":
			_advance(frame)
			game.place_instability(-1, str(target), amount)
			return false
		"black_rose_damage_all_evocations":
			_advance(frame)
			game.deal_damage_to_evocation(-1, target, amount)
			return false
		"heal_all_evocations":
			_advance(frame)
			for owner in target.damage_cubes.duplicate():
				game.heal_evocation_damage(target, owner, 1)
			return false
		"draw_event_from_moon":
			_advance(frame)
			var draw_context: Dictionary = context.duplicate()
			draw_context.erase("resume_black_rose")
			game.draw_event(int(context.get("drawing_player_index", game.crown_owner_id)), draw_context, int(effect.get("moon", 1)))
			return false

	var player_index: int = int(target)
	var player = game.players[player_index]
	var mage = player.mage
	var options: Array = []
	var prompt: String = context.event.event_name if context.get("event") != null else "Event"
	match kind:
		"each_mage_may_draw_library":
			if _supplied_choice(frame, context, "event_library_choices", player_index):
				pass
			else:
				options.append(_option("decline", "", "Decline"))
				for school in game.active_school_ids:
					if not game.get_school_library(school).is_empty() or not game.get_school_discard(school).is_empty():
						options.append(_option("school:" + school, school, school.capitalize()))
				if not _choose(game, frame, player_index, options, prompt):
					return false
			var school: String = str(frame.choice)
			_advance(frame)
			if not school.is_empty() and game.is_school_active(school):
				for i in range(amount):
					var spell = game.draw_from_school_library(school)
					if spell != null:
						player.hand.append(spell)
		"each_mage_may_place_model", "each_mage_lose_power_then_place_from_cell", "each_mage_place_from_cell":
			var from_cell: bool = kind != "each_mage_may_place_model"
			if kind == "each_mage_lose_power_then_place_from_cell" and not bool(frame.get("cost_paid", false)):
				frame["cost_paid"] = true
				game.add_player_power(player_index, -int(effect.get("power_loss", 1)))
				return false
			if not from_cell:
				options.append(_option("decline", "", "Decline"))
			var rooms: Array = game.get_player_cell_exit_room_ids(player_index) if from_cell else game.room_id_by_coord.values()
			for room_id in rooms:
				options.append({"token": "room:" + str(room_id), "value": room_id, "room_id": room_id, "name": room_id})
			if not _supplied_choice(frame, context, "event_mage_destinations", player_index) and not _choose(game, frame, player_index, options, prompt, "event_cell_destination" if from_cell else "event_room_destination"):
				return false
			var destination: String = str(frame.get("choice", ""))
			_advance(frame)
			if destination in rooms:
				# Placement is not movement: Dislocation can place from a Cell anywhere.
				mage.room_id = destination
				mage.room_coord = game.room_id_to_coord(destination)
				mage.in_cell = false
				game.refresh_model_tokens()
		"each_mage_may_summon_evocation":
			options.append(_option("decline", "", "Decline"))
			var evocation_id: String = str(effect.get("evocation_id", "cadaver"))
			var copies: int = int(game.evocation_database.get_evocation(evocation_id).get("copies", 0))
			for owner in game.players:
				for evocation in owner.evocations:
					if evocation.evocation_id == evocation_id:
						copies -= 1
			if not mage.in_cell and copies > 0:
				options.append(_option("summon", mage.room_id, "Summon " + str(effect.get("evocation_id", "cadaver"))))
			if not _supplied_choice(frame, context, "event_summon_choices", player_index) and not _choose(game, frame, player_index, options, prompt):
				return false
			var room_id: String = str(frame.choice)
			if copies <= 0:
				_advance(frame)
				return false
			if room_id == mage.room_id and not mage.in_cell and not player.has_free_evocation_slot():
				if not frame.has("replacement"):
					var replacements: Array = []
					for i in range(player.evocations.size()):
						var evocation: EvocationState = player.evocations[i]
						replacements.append({"token": "evocation:%d:%d" % [player_index, i], "value": evocation,
							"owner_id": player_index, "evocation_index": i, "name": evocation.get_display_name()})
					game.request_effect_choice(player_index, "event_replace_evocation", frame, "replacement", replacements, 1, 1, prompt + ": choose an Evocation to replace.")
					return false
				var replaced: EvocationState = frame.replacement
				# Rulebook: replacing an Evocation is not a removal/defeat trigger.
				game.finalize_evocation_removal(replaced)
				return false
			_advance(frame)
			if not mage.in_cell and room_id == mage.room_id:
				game.summon_evocation(player_index, str(effect.get("evocation_id", "cadaver")), room_id)
		"each_mage_discard_hand_or_lose_power", "each_mage_discard_solved_quest_or_lose_power":
			var quests: bool = kind == "each_mage_discard_solved_quest_or_lose_power"
			var cards: Array = player.completed_quests.filter(func(q): return q.is_solved()) if quests else player.hand
			for i in range(cards.size()):
				options.append(_option("card:" + str(i), cards[i], cards[i].get_name() if quests else cards[i].card_name))
			if not options.is_empty() and not _choose(game, frame, player_index, options, prompt):
				return false
			var card = frame.get("choice")
			_advance(frame)
			if card == null:
				game.add_player_power(player_index, -int(effect.get("power_loss", 1)))
			elif quests:
				game.quest_manager.discard_completed_quest(game, player_index, card)
			else:
				game.discard_player_spell(player_index, card)
		"each_mage_optional_give_trophy_then_place_instability":
			options.append(_option("decline", -1, "Decline"))
			for i in range(player.trophies.size()):
				options.append(_option("trophy:" + str(i), i, "Give trophy of Player " + str(player.trophies[i] + 1)))
			if not _choose(game, frame, player_index, options, prompt):
				return false
			var trophy_index: int = int(frame.choice)
			_advance(frame)
			if trophy_index >= 0 and trophy_index < player.trophies.size():
				game.black_rose_trophies.append(player.trophies[trophy_index])
				player.trophies.remove_at(trophy_index)
				if not mage.in_cell:
					game.place_instability(player_index, mage.room_id, amount)
		"each_mage_optional_lose_power_draw_forgotten":
			options.append(_option("decline", false, "Decline"))
			var cost: int = int(effect.get("power_loss", 2))
			if player.power >= cost:
				options.append(_option("accept", true, "Lose %d Power and draw a Forgotten Spell" % cost))
			if not _choose(game, frame, player_index, options, prompt):
				return false
			var accepted: bool = bool(frame.choice)
			_advance(frame)
			if accepted:
				game.add_player_power(player_index, -cost)
				for i in range(amount):
					game.draw_forgotten_spell(player_index)
		"black_rose_convert_damage_all_mages_then_damage_if_none":
			if bool(frame.get("damage_stage", false)):
				_advance(frame)
				if not player_index in frame.get("converted_players", []):
					game.deal_damage(-1, player_index, int(effect.get("damage", 2)), "event")
				return false
			var ordinals: Dictionary = {}
			for i in range(mage.damage_cubes.size()):
				var owner: int = mage.damage_cubes[i]
				if owner != -1:
					var ordinal: int = int(ordinals.get(owner, 0))
					ordinals[owner] = ordinal + 1
					options.append({"token": "damage:%d:%d" % [owner, ordinal], "value": i, "cube_player_index": player_index, "label": "Damage of Player %d" % (owner + 1)})
			var maximum: int = mini(int(effect.get("convert_max", 4)), options.size())
			if maximum > 0 and not frame.has("choice"):
				game.request_effect_choice(game.crown_owner_id, "event_convert_damage", frame, "choice", options, 0, maximum, prompt + ": choose up to %d cubes on Player %d (Choice of the Crown)." % [maximum, player_index + 1])
				return false
			var selected = frame.get("choice", [])
			var indices: Array = selected if selected is Array else [selected]
			var converted: int = 0
			for index in indices:
				if index == null or int(index) < 0 or int(index) >= mage.damage_cubes.size():
					continue
				var owner: int = mage.damage_cubes[int(index)]
				if owner != -1 and game.take_owner_cubes(-1, 1) == 1:
					game.return_owner_cubes(owner, 1)
					mage.damage_cubes[int(index)] = -1
					converted += 1
			if converted > 0:
				if not frame.has("converted_players"):
					frame["converted_players"] = []
				frame.converted_players.append(player_index)
			_advance(frame)
		"heal_non_black_rose_damage_then_damage_mages_without_black_rose_damage":
			_advance(frame)
			if bool(frame.get("damage_stage", false)):
				if not -1 in mage.damage_cubes:
					game.deal_damage(-1, player_index, int(effect.get("damage", 2)), "event")
			else:
				for owner in mage.damage_cubes.duplicate():
					if owner != -1:
						game.heal_damage(player_index, owner, 1)
		"each_mage_black_rose_damage_by_owned_evocation_strength_or_lose_power":
			_advance(frame)
			if player.evocations.is_empty():
				game.add_player_power(player_index, -int(effect.get("power_loss", 1)))
			else:
				var strength: int = 0
				for evocation in player.evocations:
					strength += evocation.strength
				game.deal_damage(-1, player_index, strength, "event")
		"each_mage_draw_quest_from_moon":
			_advance(frame)
			for i in range(amount):
				game.quest_manager.draw_quest(game, player_index, int(effect.get("moon", 3)))
		"each_mage_without_completed_quests_gain_power":
			_advance(frame)
			if player.completed_quests.filter(func(q): return q.is_completed()).is_empty():
				game.add_player_power(player_index, amount)
		"each_mage_lose_power":
			_advance(frame)
			game.add_player_power(player_index, -amount)
		"crown_owner_gain_power":
			_advance(frame)
			game.add_player_power(player_index, amount)
		"return_all_mages_to_cells":
			_advance(frame)
			game.place_mage_in_cell(player_index)
		"black_rose_damage_all_mages":
			_advance(frame)
			game.deal_damage(-1, player_index, amount, "event")
		_:
			push_error("Unknown Event effect: " + kind)
			return true
	return false

func _advance(frame: Dictionary) -> void:
	frame["cursor"] = int(frame.get("cursor", 0)) + 1
	frame.erase("choice")
	frame.erase("cost_paid")
	frame.erase("replacement")

func _play_order(context: Dictionary) -> Array:
	var game = context.game
	# Taking the Crown during an Event changes the first Mage next phase only.
	return context.get("play_order", game.current_phase_play_order if not game.current_phase_play_order.is_empty() else game.get_play_order()).duplicate()

func _option(token: String, value, label: String) -> Dictionary:
	return {"token": token, "value": value, "label": label}

func _choose(game, frame: Dictionary, player_index: int, options: Array, prompt: String, kind: String = "event_choice") -> bool:
	if frame.has("choice"):
		return true
	if options.size() <= 1:
		frame["choice"] = options[0].value if options.size() == 1 else null
		return true
	game.request_effect_choice(player_index, kind, frame, "choice", options, 1, 1, prompt)
	return false

func _supplied_choice(frame: Dictionary, context: Dictionary, key: String, player_index: int) -> bool:
	if context.get(key, {}).has(player_index):
		frame["choice"] = context[key][player_index]
		return true
	return false
