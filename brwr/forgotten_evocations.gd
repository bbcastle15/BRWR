class_name ForgottenEvocations
extends RefCounted

static func all_models(game) -> Array:
	var result: Array = []
	for player in game.players:
		result.append_array(player.evocations)
	return result

static func ability(game, ev: EvocationState, kind: String) -> Dictionary:
	for data in game.get_evocation_abilities(ev):
		if data.get("type") == kind:
			return data
	return {}

static func extended(game, ev: EvocationState) -> bool:
	return bool(game.evocation_database.get_evocation(ev.evocation_id).get("forgotten", false)) or ev.archetype == "nightmare" or not ev.upgrades.is_empty() or not ability(game, ev, "on_activation_start").is_empty() or not ability(game, ev, "optional_attack_replacement").is_empty() or not ability(game, ev, "replace_attack").is_empty()

static func can_activate(game, ev: EvocationState) -> bool:
	if ev == null or ev.archetype == "equipment" or ev.is_defeated() or not game.is_evocation_in_play(ev):
		return false
	if ev.assigned_mage >= 0 and game.players[ev.assigned_mage].mage.in_cell:
		return false
	for other in all_models(game):
		if other != ev and not ability(game, other, "block_other_non_nightmare_activations").is_empty() and ev.archetype != "nightmare":
			return false
	return true

static func can_remove(game, ev: EvocationState, context: Dictionary) -> bool:
	if not game.is_evocation_in_play(ev):
		return false
	if not ability(game, ev, "immortal_while_trophies").is_empty() and not ev.stored_trophies.is_empty():
		return false
	if str(context.get("resolver_kind", "spell")) == "spell":
		if not ability(game, ev, "cannot_be_removed_by_spells").is_empty() or not ability(game, ev, "ignore_spell_effects").is_empty():
			return false
		if ev.owner_id != int(context.get("caster_id", -1)) and bool(game.evocation_database.get_evocation(ev.evocation_id).get("forgotten", false)) and not bool(context.get("spell_forgotten", false)):
			return false
	return true

static func bonus_strength(game, ev: EvocationState, controller: int = -2) -> int:
	var amount: int = 0
	if controller == -2:
		controller = game.get_evocation_controller_id(ev)
	for item in game.get_evocation_abilities(ev):
		match str(item.type):
			"strength_if_room_instability":
				var room = game.get_room_by_id(ev.room_id)
				if room != null and not room.instability_cubes.is_empty(): amount += int(item.amount)
			"strength_per_event": amount += ForgottenRules.event_count(game)
			"strength_per_jinxed_mage":
				for player in game.players:
					if player.mage != null and not player.mage.jinxes.is_empty():
						amount += 1
			"strength_per_damage": amount += ev.get_damage() * int(item.get("amount_per_damage", 1))
			"strength_per_stored_cube": amount += game.get_evocation_stored_owner_cube_count(ev)
			"strength_per_stored_trophy": amount += mini(ev.stored_trophies.size(), int(item.get("max", 3)))
			"strength_per_other_nightmare":
				for other in all_models(game):
					if other != ev and other.archetype == "nightmare" and game.is_lodge_room_id(other.room_id) and (other.assigned_mage < 0 or not game.players[other.assigned_mage].mage.in_cell):
						amount += 1
	for other in all_models(game):
		if game.get_evocation_controller_id(other) == controller and not ability(game, other, "event_strength_aura").is_empty() and game.is_room_within_effect_range(other.room_id, ev.room_id, 1):
			amount += ForgottenRules.event_count(game)
	if controller >= 0:
		amount += ForgottenPassives.value(game.players[controller], "evocation_strength_bonus")
	return amount

static func activation_context(game, frame: Dictionary) -> Dictionary:
	var ev: EvocationState = frame.evocation
	var context: Dictionary = frame.get("forgotten_context", {})
	if context.is_empty():
		context = {"game": game, "caster_id": int(frame.controller_id), "source_evocation": ev,
			"resolver_kind": "evocation", "source_kind": "evocation", "evocation_activation_frame": {"strength_bonus": 0}}
		frame["forgotten_context"] = context
	context["caster_room_id"] = ev.room_id
	context["effect_origin_room_id"] = ev.room_id
	return context

static func queue_abilities(game, frame: Dictionary, timing: String) -> void:
	var context := activation_context(game, frame)
	var effects: Array = []
	for item in game.get_evocation_abilities(frame.evocation):
		if item.get("type") == timing:
			var sentences: Array = item.get("effects", [])
			if bool(item.get("optional", false)):
				effects.append({"type": "optional_effect", "effects": sentences})
			else:
				effects.append_array(sentences)
	if not effects.is_empty():
		ForgottenRules.queue(game, effects, context)

static func process_activation(game, frame: Dictionary) -> bool:
	var ev: EvocationState = frame.evocation
	if bool(frame.get("activation_ended", false)) or not can_activate(game, ev):
		return true
	var controller: int = int(frame.controller_id)
	# Nightmares' mandatory Black Rose attacks have no player decisions.
	if ev.assigned_mage >= 0:
		return process_nightmare_attack(game, frame)
	var context := activation_context(game, frame)
	var step: String = str(frame.get("forgotten_step", "start"))
	match step:
		"start":
			frame["forgotten_step"] = "order"
			queue_abilities(game, frame, "on_activation_start")
			return false
		"order":
			var legacy: Dictionary = frame.get("context", {})
			if legacy.has("evocation_attack_timing"):
				frame["order"] = str(legacy.evocation_attack_timing)
			elif ev.speed <= 0:
				frame["order"] = "before"
			elif not DruidicRules.choose(game, controller, frame, "order", [
				{"token": "before", "value": "before", "name": "Attack, then move"},
				{"token": "after", "value": "after", "name": "Move, then attack"}], "Choose the order for " + ev.evocation_name + "."):
				return false
			frame["forgotten_step"] = "move" if frame.order in ["after", "none"] else "before_attack"
			return false
		"move":
			var moved: int = int(frame.get("extended_moved", 0))
			var speed: int = maxi(0, ev.speed + int(frame.get("context", {}).get("evocation_activation_speed_bonus", 0)))
			if bool(ev.definition.get("fixed_stats", false)): speed = ev.speed
			var legacy: Dictionary = frame.get("context", {})
			var options: Array = []
			if legacy.has("evocation_move_room_ids"):
				var path: Array = legacy.evocation_move_room_ids
				if moved < path.size() and moved < speed:
					game.move_evocation_to_room_id(ev, str(path[moved]), 1)
					frame["extended_moved"] = moved + 1
					return false
			elif moved < speed:
				options = ForgottenRules.rooms(game, context, 1)
				if not DruidicRules.choose(game, controller, frame, "move_room", options, "Move " + ev.evocation_name + ", or select its Room to stop.", false, "movement_destination"):
					return false
				var room_id: String = str(frame.get("move_room", ev.room_id))
				frame.erase("move_room")
				if room_id != ev.room_id and game.move_evocation_to_room_id(ev, room_id, 1):
					frame["extended_moved"] = moved + 1
					return false
			frame["forgotten_step"] = "before_attack" if frame.order == "after" else "end"
			return false
		"before_attack":
			frame["forgotten_step"] = "target"
			# Wukong chooses its destination before the attack target. Other
			# before-attack abilities (Rubedo/Cacus) need the target first.
			if not ability(game, ev, "before_attack").is_empty() and ability(game, ev, "before_attack").get("effects", []).any(func(e): return e.get("type") == "place_evocation_in_any_room"):
				queue_abilities(game, frame, "before_attack")
				frame["pre_ability_done"] = true
			return false
		"target":
			var optional_replacement := ability(game, ev, "optional_attack_replacement")
			if not optional_replacement.is_empty():
				if not DruidicRules.choose(game, controller, frame, "attack_mode", [
					{"token": "attack", "value": "attack", "name": "Physical Attack"},
					{"token": "replace", "value": "replace", "name": "Place 1 Instability instead"}], "Choose the Attack Effect for " + ev.evocation_name + "."):
					return false
				if frame.get("attack_mode") == "replace":
					frame["forgotten_step"] = "after_attack"
					frame["attack_skipped"] = true
					ForgottenRules.queue(game, optional_replacement.effects, context)
					return false
			var replacement := ability(game, ev, "replace_attack")
			if not replacement.is_empty():
				frame["forgotten_step"] = "replacement"
				return false
			var range_value: int = game.get_evocation_attack_range(ev)
			var area := ability(game, ev, "attack_room")
			var options: Array = ForgottenRules.rooms(game, context, int(area.get("range", 0))) if not area.is_empty() else ForgottenRules.models(game, context, "model", range_value, "", false)
			options = options.filter(func(o): return not (o.get("value") is Dictionary and o.value.get("evocation") != null and not ability(game, o.value.evocation, "cannot_be_physically_attacked").is_empty()))
			options = options.filter(func(o): return not (o.get("value") is Dictionary and o.value.get("target_type") == "mage" and ForgottenPassives.value(game.players[int(o.value.player_index)], "cannot_be_evocation_attack_target") > 0))
			if not DruidicRules.choose(game, controller, frame, "attack_target", options, "Choose the target for " + ev.evocation_name + ".", true, "secondary_room" if not area.is_empty() else "model_target"):
				return false
			var selected = frame.get("attack_target")
			if selected == null:
				frame["forgotten_step"] = "after_attack"
				frame["attack_skipped"] = true
				return false
			var nested := ForgottenRules.target_context(context, selected)
			context.merge(nested, true)
			frame["forgotten_step"] = "attack"
			if not bool(frame.get("pre_ability_done", false)):
				queue_abilities(game, frame, "before_attack")
			return false
		"attack":
			frame["forgotten_step"] = "after_attack"
			var amount: int = game.get_evocation_effective_strength(ev, int(frame.get("strength_bonus", 0)) + int(context.evocation_activation_frame.get("strength_bonus", 0)))
			amount += bonus_strength(game, ev, controller) - bonus_strength(game, ev)
			if context.get("spell_target_type") == "mage" and not ability(game, ev, "steal_power_instead_mage_attack").is_empty():
				ForgottenRules.queue(game, [{"type": "steal_power", "amount": 1}], context)
				return false
			DruidicRules.on_evocation_attack(game, ev, controller)
			attack_damage(game, ev, controller, amount, context)
			return false
		"replacement":
			var data := ability(game, ev, "replace_attack")
			var selected: Array = frame.get("replacement_choices", [])
			if selected.size() >= int(data.get("choose_count", 1)):
				frame["forgotten_step"] = "after_attack"
				return false
			var options: Array = []
			for i in data.choices.size():
				if not i in selected:
					options.append({"token": "attack_effect:%d" % i, "value": i, "name": str(data.choices[i].label)})
			if not DruidicRules.choose(game, controller, frame, "replacement_choice", options, "Choose the Physical Attack Effect.", bool(data.get("optional", false))):
				return false
			var choice = frame.get("replacement_choice")
			frame.erase("replacement_choice")
			if choice == null:
				frame["forgotten_step"] = "after_attack"
				return false
			selected.append(int(choice))
			frame["replacement_choices"] = selected
			ForgottenRules.queue(game, data.choices[int(choice)].effects, context)
			return false
		"after_attack":
			frame["forgotten_step"] = "repeat"
			# Wukong's second placement belongs to the activation even if there
			# was no legal attack target. Damage-dependent abilities do not.
			if not bool(frame.get("attack_skipped", false)) or ev.evocation_id == "sun_wukong":
				queue_abilities(game, frame, "after_attack")
			return false
		"repeat":
			frame["forgotten_step"] = "move" if frame.order == "before" else "end"
			if not ability(game, ev, "attack_again_if_survived").is_empty() and not bool(frame.get("repeated", false)) and not bool(frame.get("attack_skipped", false)):
				var target: int = int(context.get("target_player_index", -1))
				var target_ev: EvocationState = context.get("target_evocation")
				if (target >= 0 and not game.players[target].mage.in_cell) or (target_ev != null and game.is_evocation_in_play(target_ev)):
					frame["repeated"] = true
					frame.erase("attack_target")
					frame["forgotten_step"] = "target"
			return false
		"end":
			frame["forgotten_step"] = "finish"
			queue_abilities(game, frame, "on_activate")
			return false
		"finish":
			var original: Dictionary = frame.get("context", {})
			original["last_activated_evocation"] = ev
			if not ability(game, ev, "extra_phase_activation_then_remove").is_empty() and game.current_phase == game.PHASE_EVOCATION and not bool(frame.get("warscratch_checked", false)):
				if bool(original.get("warscratch_extra", false)):
					game.emit_evocation_defeated_or_removed(ev, "removed")
					game.finalize_evocation_removal(ev)
				else:
					if not DruidicRules.choose(game, controller, frame, "extra", [{"token": "extra", "value": true, "name": "Activate again, then remove"}], "Use Warscratch?", true):
						return false
					frame["warscratch_checked"] = true
					if frame.get("extra") == true:
						game.activate_evocation(ev, controller, {"warscratch_extra": true})
			return true
	return true

static func attack_damage(game, ev: EvocationState, controller: int, amount: int, context: Dictionary) -> void:
	var targets: Array = []
	if context.get("spell_target_type") == "room":
		for option in ForgottenRules.models(game, context, "model", 0, str(context.target_room_id), false):
			targets.append(option.value)
	else:
		targets.append({"target_type": "evocation", "evocation": context.target_evocation} if context.get("target_evocation") != null else {"target_type": "mage", "player_index": int(context.get("target_player_index", -1))})
	for target in targets:
		if target.target_type == "mage":
			if game._valid_evocation_attack_mage(ev, controller, int(target.player_index)):
				game.deal_damage_from_evocation(ev, int(target.player_index), amount, controller)
		else:
			if game._valid_evocation_attack_evocation(ev, controller, target.evocation):
				game.deal_damage_to_evocation(controller, target.evocation, amount, [], "evocation_attack", "evocation", ev)

static func resolve_assignment(game, effect: Dictionary, context: Dictionary) -> bool:
	var caster: int = int(context.caster_id)
	var target: int = int(context.get("target_player_index", -1))
	if effect.type == "activate_assigned_nightmares":
		if target >= 0:
			for ev in game.players[target].evocations:
				if ev.assigned_mage == target:
					game.activate_evocation(ev, caster, {}, int(effect.get("strength_bonus", 0)))
		return true
	if bool(effect.get("choose_mage", false)):
		var options := ForgottenRules.models(game, context, "mage")
		if not DruidicRules.choose(game, caster, context, "nightmare_mage", options, "Assign the Nightmare to a Mage.", false, "mage_target"):
			return false
		var value = context.get("nightmare_mage")
		target = int(value.player_index) if value is Dictionary else caster
	if target < 0 or game.get_available_evocation_copies(str(effect.evocation_id)) <= 0:
		context.erase("nightmare_mage")
		return true
	var slots: Array = []
	for i in range(1, 4):
		slots.append({"token": "slot:%d" % i, "value": i, "name": "Evocation slot %d" % i})
	if not DruidicRules.choose(game, caster, context, "nightmare_slot", slots, "Choose the slot for the assigned Nightmare."):
		return false
	var data: Dictionary = game.evocation_database.get_evocation(str(effect.evocation_id))
	var ev := EvocationState.new(data.id, data.name, data.archetype, int(data.health), int(data.strength), int(data.speed), -1)
	ev.definition = data
	ev.assigned_mage = target
	ev.assigned_slot = int(context.get("nightmare_slot", 1))
	ev.board_number = 100
	for other in game.players[target].evocations:
		ev.board_number = maxi(ev.board_number, other.board_number + 1)
	ev.room_id = game.players[target].mage.room_id
	game.players[target].evocations.append(ev)
	context["last_assigned_nightmare"] = ev
	context.erase("nightmare_mage")
	context.erase("nightmare_slot")
	game.refresh_model_tokens()
	game.refresh_all_player_boards()
	return true

static func process_nightmare_attack(game, frame: Dictionary) -> bool:
	var ev: EvocationState = frame.evocation
	if bool(frame.get("nightmare_attacked", false)):
		return true
	frame["nightmare_attacked"] = true
	var controller: int = int(frame.controller_id)
	# FAQ: an Umbra assigned to the Avatar also spares the Evocation in its slot.
	if AvatarRules.is_avatar(game, ev.assigned_mage) and AvatarRules.cube_owner(game, controller) == -1: return true
	game.deal_damage_from_evocation(ev, ev.assigned_mage, game.get_evocation_effective_strength(ev, int(frame.get("strength_bonus", 0))), controller)
	var extra := ability(game, ev, "damage_assigned_slot")
	if not extra.is_empty():
		for other in game.players[ev.assigned_mage].evocations:
			if other.assigned_mage < 0 and other.board_number == ev.assigned_slot:
				game.deal_damage_to_evocation(controller, other, int(extra.amount), [], "evocation", "evocation", ev)
	return false

static func sync_assigned(game) -> void:
	for ev in all_models(game):
		if ev.assigned_mage >= 0:
			var mage = game.players[ev.assigned_mage].mage
			ev.room_id = mage.room_id
			ev.owner_id = ev.assigned_mage if mage.in_cell else -1
			ev.controller_id = ev.owner_id

static func on_summon(game, ev: EvocationState) -> void:
	if not ability(game, ev, "store_trophies_on_summon").is_empty():
		for i in game.players.size():
			if i != ev.owner_id:
				ev.stored_trophies.append(i)
	var upgrades := ability(game, ev, "upgrades_on_summon")
	if not upgrades.is_empty():
		var context: Dictionary = {"game": game, "caster_id": ev.owner_id, "last_summoned_evocation": ev, "resolver_kind": "evocation"}
		var effects: Array = []
		for i in int(upgrades.amount):
			effects.append({"type": "assign_upgrade"})
		ForgottenRules.queue(game, effects, context)

static func on_event(game, event: GameEvent) -> void:
	if event.event_type == "evocation_defeated_or_removed" and event.action_type in ["defeated", "removed"] and event.target_evocation != null:
		var loss := ability(game, event.target_evocation, "convert_instability_on_defeat_or_removal")
		var controller: int = game.get_evocation_controller_id(event.target_evocation)
		if not loss.is_empty() and controller >= 0 and game.is_lodge_room_id(event.target_room_id):
			ForgottenRules.queue(game, [{"type": "convert_instability", "amount": int(loss.amount)}],
				{"game": game, "caster_id": controller, "resolver_kind": "evocation", "source_evocation": event.target_evocation,
					"spell_target_type": "room", "target_room_id": event.target_room_id})
	if event.event_type == "mage_enters_room" or event.event_type == "mage_placed_in_cell":
		sync_assigned(game)
	for ev in all_models(game).duplicate():
		var controller: int = game.get_evocation_controller_id(ev)
		if event.event_type == "mage_defeated":
			if not ev.stored_trophies.is_empty():
				ev.stored_trophies.pop_back()
				if ev.is_defeated():
					game.queue_resolution({"type": "evocation_damage", "evocation": ev, "step": "after_post_event", "was_defeated": false, "actual_damage": 0})
			if event.source_evocation == ev and not ability(game, ev, "extra_trophy_on_defeat").is_empty() and controller >= 0:
				game.gain_player_trophy(controller, event.target_player_index)
			if not ability(game, ev, "other_mage_defeat_trophy").is_empty() and controller >= 0 and event.target_player_index != controller:
				game.gain_player_trophy(controller, event.target_player_index)
		if event.event_type == "quest_solved" and controller >= 0 and event.source_player_index != controller and not ability(game, ev, "other_mage_quest_power").is_empty():
			game.add_player_power(controller, 1)
		if event.event_type == "damage_inflicted" and event.target_evocation == ev:
			if not ability(game, ev, "store_cube_when_damaged").is_empty() and controller >= 0:
				var key: int = game._evocation_storage_key(ev)
				game.stored_evocation_owner_cubes[key] = int(game.stored_evocation_owner_cubes.get(key, 0)) + game.take_owner_cubes(ev.owner_id, 1)
			var reflect := ability(game, ev, "reflect_damage")
			if not reflect.is_empty() and event.source_model_type != "black_rose":
				var amount: int = event.amount + int(reflect.bonus)
				if event.source_evocation != null:
					game.deal_damage_to_evocation(controller, event.source_evocation, amount, [], "evocation", "evocation", ev)
				elif event.source_player_index >= 0:
					game.deal_damage_from_evocation(ev, event.source_player_index, amount, controller)
		if event.event_type == "damage_inflicted" and event.source_evocation == ev and controller >= 0 and not ability(game, ev, "power_when_inflicts_damage").is_empty():
			game.add_player_power(controller, 1)
		if event.event_type == "evocation_defeated_or_removed" and event.target_evocation == ev and event.action_type == "defeated":
			var recover := ability(game, ev, "return_spell_on_defeat")
			if not recover.is_empty():
				return_forgotten(game, ev.owner_id, str(recover.spell_id))
		if event.event_type == "model_enters_room" and event.source_evocation == ev and controller >= 0:
			queue_abilities(game, {"evocation": ev, "controller_id": controller}, "on_room_entry")

static func return_forgotten(game, owner: int, id: String) -> void:
	var found: SpellCardState = null
	for frame in game.resolution_stack:
		var spell: SpellCardState = frame.get("spell")
		if spell == null and frame.get("ready_spell") != null:
			spell = frame.ready_spell.spell
		if spell != null and spell.id == id:
			found = spell
			var context: Dictionary = frame.get("context", {})
			context["returned_to_hand"] = true
			frame["context"] = context
	for deck in [game.forgotten_deck, game.forgotten_removed_from_game]:
		for card in deck.duplicate():
			if card.id == id:
				deck.erase(card)
				found = card
	for i in game.players.size():
		var player = game.players[i]
		for deck in [player.hand, player.memories, player.grimoire]:
			for card in deck.duplicate():
				if card.id == id:
					deck.erase(card)
					found = card
		for deck in [player.ready_spells, player.revealed_spells, player.active_spells]:
			for state in deck.duplicate():
				if state.spell.id == id:
					found = state.spell
					deck.erase(state)
		if player.quick_spell != null and player.quick_spell.spell.id == id:
			found = player.quick_spell.spell
			player.quick_spell = null
		if found != null:
			game._clear_player_board_spell_by_spell(i, found)
	if found != null and owner >= 0:
		game.players[owner].hand.append(found)

static func process_frame(game, frame: Dictionary) -> bool:
	if frame.type == "forgotten_nightmare_phase":
		var models: Array = frame.get("remaining", [])
		if not frame.has("remaining"):
			models = all_models(game).filter(func(ev): return ev.assigned_mage >= 0 and can_activate(game, ev))
			frame["remaining"] = models
		if models.is_empty():
			return true
		var options: Array = []
		for ev in models:
			if can_activate(game, ev):
				options.append({"token": "nightmare:%d" % ev.get_instance_id(), "value": ev, "name": ev.evocation_name + " · " + game.players[ev.assigned_mage].player_name})
		if options.is_empty():
			return true
		if not DruidicRules.choose(game, maxi(0, game.crown_owner_id), frame, "next", options, "Choose the next Nightmare to activate.", false, "evocation_target"):
			return false
		var selected: EvocationState = frame.get("next")
		frame.erase("next")
		models.erase(selected)
		if selected != null:
			game.activate_evocation(selected, -1, {})
		return false
	if frame.type == "forgotten_nightmare_defeat":
		var victim: int = int(frame.victim)
		for ev in game.players[victim].evocations.duplicate():
			if ev.assigned_mage != victim:
				continue
			if ability(game, ev, "reassign_on_defeat").is_empty():
				game.finalize_evocation_removal(ev)
			elif frame.get("source_evocation") == ev:
				var context: Dictionary = frame.context
				context.merge({"game": game, "caster_id": victim}, true)
				var options := ForgottenRules.models(game, context, "mage")
				if not DruidicRules.choose(game, victim, context, "new_mage", options, "Assign Cthully to another Mage.", false, "mage_target"):
					return false
				var selected = context.get("new_mage")
				if selected is Dictionary:
					var target: int = int(selected.player_index)
					game.players[victim].evocations.erase(ev)
					ev.assigned_mage = target
					game.players[target].evocations.append(ev)
					sync_assigned(game)
		return true
	return true
