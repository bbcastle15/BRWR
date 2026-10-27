class_name AvatarEffects
extends RefCounted

# Command sections run on Game's existing stack. Nested damage, reactions,
# defeat and player choices finish before the next printed sentence starts.
static func process_section(game, frame: Dictionary) -> bool:
	var section: Dictionary = frame.section
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	var context: Dictionary = frame.context
	match str(frame.get("stage", "target")):
		"target":
			context.merge({"game": game, "caster_id": actor, "caster_room_id": mage.room_id,
				"spell_id": frame.card.id, "spell_type": str(section.get("type", "")),
				"spell_element": str(section.get("element", "")), "resolver_kind": "spell",
				"spell_target_type": section.get("target", "special"), "resolving_spell": frame.card}, false)
			if bool(frame.get("reaction", false)):
				var event: GameEvent = frame.get("event")
				context["trigger_event"] = event
				context["target_player_index"] = event.source_player_index
				context["target_model_type"] = "mage"
				context["spell_target_type"] = "mage"
			elif section.get("target") in ["mage", "area"]:
				var options: Array = AvatarRules.model_options(game, int(section.range)) if section.target == "mage" else AvatarRules.room_options(game, int(section.range))
				options = AvatarRules.priority(game, options, int(section.priority))
				if not AvatarRules.choose(game, frame, "target", options, frame.card.card_name + " · target", "room_target" if section.target == "area" else "model_target"): return false
				if frame.target == null: return true
				if section.target == "mage":
					context["target_player_index"] = int(frame.target.player_index)
					context["target_model_type"] = "mage"
				else:
					context["target_room_id"] = str(frame.target)
					context["target_model_type"] = "room"
			elif section.get("target") == "self":
				context["target_player_index"] = actor
			frame["stage"] = "announce"
			return false
		"announce":
			frame["stage"] = "instability"
			if section.kind == "spell":
				var event := GameEvent.new("spell_cast_started")
				event.source_player_index = actor
				event.source_model_type = "mage"
				event.source_room_id = mage.room_id
				game.process_game_event(event)
			return false
		"instability":
			frame["stage"] = "effects"
			if bool(section.get("instability", false)) and not mage.in_cell:
				game.place_instability(actor, mage.room_id, 1)
			return false
		"effects":
			var index: int = int(frame.get("index", 0))
			var effects: Array = section.effects
			if index >= effects.size():
				frame["stage"] = "done"
				return false
			var effect: Dictionary = effects[index]
			if not frame.has("effect_frame"): frame["effect_frame"] = {"effect": effect, "context": context}
			if section.kind != "physical" and not frame.effect_frame.get("announced", false):
				frame.effect_frame["announced"] = true
				announce_effect(game, effect, context)
				return false
			if not resolve(game, frame.effect_frame): return false
			game.log_resolved_effect(effect, context)
			frame.erase("effect_frame")
			frame["index"] = index + 1
			return false
		"done":
			frame["stage"] = "finished"
			var event := GameEvent.new("physical_action_performed" if section.kind == "physical" else "spell_resolved")
			event.source_model_type = "mage"
			event.source_player_index = actor
			event.source_room_id = mage.room_id
			event.action_type = "avatar_physical" if section.kind == "physical" else "spell"
			event.data["spell_type"] = section.get("type", "")
			game.process_game_event(event)
			if section.kind == "physical": ForgottenAttachments.physical_action_finished(game, actor)
			return false
	return true

static func _done(frame: Dictionary) -> bool:
	frame["done"] = true
	return true

static func announce_effect(game, effect: Dictionary, context: Dictionary) -> void:
	var affected: Array = []
	var kind: String = str(effect.type)
	if kind in ["damage_each_mage", "convert_each_mage", "discard_each_hand"]:
		affected = AvatarRules.model_options(game).map(func(o): return int(o.value.player_index))
	elif kind in ["damage_models_around_target", "damage_models_around_self"] or (kind == "damage" and context.get("spell_target_type") == "area"):
		var origin: String = str(context.get("target_room_id", game.players[game.avatar.player_index].mage.room_id))
		affected = AvatarRules.model_options(game, int(effect.get("range", 0)), origin).map(func(o): return int(o.value.player_index))
	elif kind in ["damage", "damage_per_ignored", "convert_damage", "discard_hand",
		"target_power_per_missing_conversion", "target_power_per_missing_discard",
		"remove_target_evocation", "remove_per_discard", "trophy"] and context.has("target_player_index"):
		affected = [int(context.target_player_index)]
	if affected.is_empty(): return
	var event := GameEvent.new("spell_effect_about_to_resolve")
	event.source_model_type = "mage"
	event.source_player_index = game.avatar.player_index
	event.source_room_id = game.players[game.avatar.player_index].mage.room_id
	if affected.size() == 1:
		event.target_model_type = "mage"
		event.target_player_index = int(affected[0])
	event.set_meta("caput_spell_effect", true)
	event.set_meta("source_spell_context", context)
	event.set_meta("source_spell_effect", effect)
	event.set_meta("source_spell_id", str(context.get("spell_id", "")))
	event.set_meta("source_spell_type", str(context.get("spell_type", "")))
	event.set_meta("source_spell_forgotten", false)
	event.set_meta("affected_player_indices", affected)
	# Bone Shield and other Death Protections consume the same trigger through
	# event.data; keep it linked to the authoritative section context too.
	event.data = {"targets": affected, "spell_context": context}
	game.process_game_event(event)

static func _valid_target(game, context: Dictionary) -> int:
	var target: int = int(context.get("target_player_index", -1))
	if target < 0 or target >= game.players.size() or DeathEffectResolver.ignores(context, target): return -1
	if game.players[target].mage.in_cell: return -1
	return target

static func remove_evocation(game, ev: EvocationState) -> void:
	if ev != null and game.finalize_evocation_removal(ev):
		game.emit_evocation_defeated_or_removed(ev, "removed")

static func rightmost_conversion(game, cubes: Array, amount: int, room = null) -> int:
	var converted := 0
	for i in range(cubes.size() - 1, -1, -1):
		if converted >= amount: break
		var owner: int = int(cubes[i])
		if owner == -1: continue
		if game.take_owner_cubes(-1, 1) <= 0: break
		game.return_owner_cubes(owner, 1)
		if room != null: room.convert_instability_cube(owner, -1, i)
		else: cubes[i] = -1
		converted += 1
	game.refresh_all_player_boards()
	return converted

static func _damage_targets(game, frame: Dictionary, options: Array, amount: int) -> bool:
	if not frame.has("targets"):
		frame["targets"] = options
		# One printed sentence affecting several Models finishes assigning all
		# cubes before deaths return any to the pool (rulebook p.28 / FAQ).
		frame.context["sentence_damage_frames"] = []
	if frame.targets.is_empty():
		if not DeathEffectResolver.finish_sentence(game, frame.context): return false
		frame.context.erase("sentence_damage_frames")
		return _done(frame)
	var candidates: Array = frame.targets.filter(func(o): return o.value.has("player_index"))
	if candidates.is_empty(): candidates = frame.targets.duplicate()
	candidates = AvatarRules.rank(game, candidates, ["most_black_rose_damage", "most_damage"])
	# The Room is already the target. Resolve its affected Models without
	# requesting one click per Model; keep the established damage priorities.
	# Equivalent recipients use their stable enumeration order.
	var target: Dictionary = candidates[0].value
	frame.targets = frame.targets.filter(func(o): return o.value != target)
	var context: Dictionary = frame.context
	var actor: int = game.avatar.player_index
	var previous: Dictionary = game.active_effect_context
	game.active_effect_context = context
	if target.get("evocation") != null:
		game.deal_damage_to_evocation(actor, target.evocation, amount, [], "spell", "mage")
	else:
		var id: int = int(target.player_index)
		if not game.players[id].mage.in_cell and not DeathEffectResolver.ignores(context, id):
			game.deal_damage(actor, id, amount, "spell")
	game.active_effect_context = previous
	return false

static func resolve(game, frame: Dictionary) -> bool:
	if bool(frame.get("done", false)): return true
	var effect: Dictionary = frame.effect
	var context: Dictionary = frame.context
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	var target := _valid_target(game, context)
	var room_id: String = str(context.get("target_room_id", mage.room_id))
	var amount: int = int(effect.get("amount", 1))
	match str(effect.type):
		"move_toward": return _move(game, frame)
		"damage", "damage_each_mage", "damage_models_around_target", "damage_models_around_self", "damage_per_ignored":
			var options: Array = []
			match str(effect.type):
				"damage_each_mage": options = AvatarRules.model_options(game)
				"damage_models_around_target", "damage_models_around_self":
					options = AvatarRules.model_options(game, int(effect.range), mage.room_id if effect.type == "damage_models_around_self" else room_id, false)
				"damage_per_ignored":
					amount = int(context.get("ignored_damage", 0))
					if target >= 0: options = [{"value": {"player_index": target}}]
				_:
					if context.get("spell_target_type") == "area": options = AvatarRules.model_options(game, 0, room_id, false)
					elif target >= 0: options = [{"value": {"player_index": target}}]
			return _damage_targets(game, frame, options, amount)
		"convert_damage":
			context["last_converted"] = rightmost_conversion(game, game.players[target].mage.damage_cubes, amount) if target >= 0 and not game.players[target].mage.in_cell else 0
			context["conversion_requested"] = amount
		"convert_each_mage":
			for option in AvatarRules.model_options(game):
				if not DeathEffectResolver.ignores(context, int(option.value.player_index)):
					rightmost_conversion(game, game.players[int(option.value.player_index)].mage.damage_cubes, amount)
		"target_power_per_missing_conversion":
			if target >= 0: game.add_player_power(target, -maxi(0, int(context.get("conversion_requested", 0)) - int(context.get("last_converted", 0))))
		"power": game.add_player_power(actor, amount)
		"heal": return _heal(game, frame, amount)
		"instability": game.place_instability(actor, room_id, amount)
		"additional_command":
			_done(frame)
			AvatarRules.begin_activation(game, true, false)
			return true
		"summon":
			var destination: String = str(game.avatar.definition.setup_room) if effect.get("at") == "black_rose" else room_id
			var summoned: EvocationState = game.summon_evocation_for_effect(actor, str(effect.evocation_id), destination, frame)
			if game.waiting_for_player_input: return false
			context["last_summoned"] = summoned
		"activate_evocation": return _activate_evocation(game, frame)
		"activate_without_effect": return _activate_room(game, frame)
		"release_energy":
			if room_id == str(game.avatar.definition.setup_room): game.place_instability(actor, mage.room_id, 2)
		"release_force":
			if room_id == str(game.avatar.definition.setup_room): game.place_instability(actor, mage.room_id, 2)
			else:
				var room = game.get_room_by_id(room_id)
				if room != null: rightmost_conversion(game, room.instability_cubes, 1, room)
		"discard_hand": return _discard_hand(game, frame, target, amount)
		"discard_each_hand":
			if not frame.has("players"):
				frame["players"] = AvatarRules.model_options(game).map(func(o): return int(o.value.player_index)).filter(func(id): return not DeathEffectResolver.ignores(context, id))
			if frame.players.is_empty(): return _done(frame)
			if not frame.has("child"): frame["child"] = {"context": {}}
			if not _discard_hand(game, frame.child, int(frame.players[0]), amount): return false
			frame.players.pop_front()
			frame.erase("child")
			return false
		"target_power_per_missing_discard":
			if target >= 0: game.add_player_power(target, -maxi(0, int(context.get("discard_requested", 0)) - int(context.get("discarded", 0))))
		"remove_target_evocation", "remove_per_discard":
			if target < 0: return _done(frame)
			var count: int = int(context.get("discarded", 0)) if effect.type == "remove_per_discard" else 1
			if int(frame.get("removed", 0)) >= count: return _done(frame)
			var options: Array = []
			for ev in game.players[target].evocations:
				if ev.assigned_mage < 0 and ev.health <= int(effect.max_health):
					options.append({"token": "evocation:%d" % ev.get_instance_id(), "value": ev, "name": ev.get_display_name()})
			if options.is_empty(): return _done(frame)
			if not _human_choice(game, target, frame, "remove", options, "Remove one of your Evocations (Health %d or less)." % int(effect.max_health)): return false
			var ev: EvocationState = frame.remove
			frame.erase("remove")
			frame["removed"] = int(frame.get("removed", 0)) + 1
			remove_evocation(game, ev)
			return false
		"ignore_damage":
			var event: GameEvent = context.get("trigger_event")
			var ignored: int = mini(amount, maxi(0, event.amount)) if event != null else 0
			context["ignored_damage"] = ignored
			if event != null: event.amount -= ignored
		"instability_per_ignored":
			if not mage.in_cell: game.place_instability(actor, mage.room_id, int(context.get("ignored_damage", 0)))
		"ignore_spell":
			var event: GameEvent = context.get("trigger_event")
			if event != null:
				var original: Dictionary = event.get_meta("source_spell_context", event.data.get("spell_context", {}))
				var ignored: Array = original.get("ignored_spell_players", [])
				if not actor in ignored: ignored.append(actor)
				original["ignored_spell_players"] = ignored
		"trophy":
			if target >= 0: game.gain_player_trophy(actor, target)
		_:
			push_error("Unsupported Avatar Effect: " + str(effect.type))
	return _done(frame)

static func _heal(game, frame: Dictionary, amount: int) -> bool:
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	var healed: int = int(frame.get("healed", 0))
	if healed >= amount or mage.damage_cubes.is_empty() or bool(frame.get("stop", false)):
		if healed == 0: game.add_player_power(actor, int(frame.effect.get("power_if_none", 0)))
		game.add_player_power(actor, maxi(0, amount - healed) * int(frame.effect.get("power_per_missing", 0)))
		return _done(frame)
	var options: Array = []
	for owner in mage.damage_cubes:
		if options.any(func(o): return o.value == owner): continue
		options.append({"token": "heal:%d" % owner, "value": owner,
			"name": "Heal 1 Damage from Player %d" % (owner + 1)})
	if bool(frame.effect.get("up_to", false)):
		options.append({"token": "heal:stop", "value": null, "name": "Stop healing · gain Power for remaining Damage"})
	if not AvatarRules.choose(game, frame, "heal_owner", options, "Choose Damage to heal.", "avatar_heal"): return false
	var owner = frame.heal_owner
	frame.erase("heal_owner")
	if owner == null: frame["stop"] = true
	else: frame["healed"] = healed + game.heal_damage(actor, int(owner), 1)
	game.refresh_all_player_boards()
	return false

static func _human_choice(game, player: int, frame: Dictionary, key: String, options: Array, prompt: String) -> bool:
	if frame.has(key): return true
	if options.is_empty():
		frame[key] = null
		return true
	game.request_effect_choice(player, "avatar_effect", frame, key, options, 1, 1, prompt)
	return false

static func _discard_hand(game, frame: Dictionary, target: int, amount: int) -> bool:
	if bool(frame.get("done", false)): return true
	if target < 0: return _done(frame)
	var player: PlayerState = game.players[target]
	var discarded: int = int(frame.get("discarded", 0))
	frame.context["discard_requested"] = amount
	frame.context["discarded"] = discarded
	if discarded >= amount or player.hand.is_empty(): return _done(frame)
	var options: Array = []
	for card in player.hand:
		options.append({"token": "hand:%d" % card.get_instance_id(), "value": card, "name": card.card_name})
	if not _human_choice(game, target, frame, "discard", options, "Possessed · discard a Spell from your Hand."): return false
	var chosen: SpellCardState = frame.discard
	frame.erase("discard")
	if not chosen in player.hand: return false
	player.hand.erase(chosen)
	game.move_spell_to_memories_or_remove(target, chosen)
	frame["discarded"] = discarded + 1
	return false

static func _move(game, frame: Dictionary) -> bool:
	var effect: Dictionary = frame.effect
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	if not frame.has("remaining"): frame["remaining"] = game.players[actor].get_mage_speed()
	if int(frame.remaining) <= 0: return _done(frame)
	var options: Array = []
	if str(effect.color).is_empty():
		options = AvatarRules.priority(game, AvatarRules.model_options(game), int(effect.priority))
	else:
		options = AvatarRules.room_options(game).filter(func(o): return o.room_id != "throne" and str(game.get_room_by_id(o.room_id).room_data.get("color", "")) == str(effect.color))
		options = AvatarRules.rank(game, options, ["nearest"])
	if not AvatarRules.choose(game, frame, "destination", options, "Avatar movement · choose the nearest %s Room." % str(effect.color) if not str(effect.color).is_empty() else "Avatar movement · choose destination.", "room_target"): return false
	if frame.destination == null: return _done(frame)
	var destination: String = str(frame.destination) if frame.destination is String else game.players[int(frame.destination.player_index)].mage.room_id
	var from: String = mage.room_id
	if from == destination and not mage.in_cell: return _done(frame)
	var exits: Array = game.get_player_cell_exit_room_ids(actor) if mage.in_cell else game._beta_adjacent_room_ids(from)
	var moves: Array = []
	for room_id in exits:
		moves.append({"token": "room:" + room_id, "value": room_id, "room_id": room_id, "name": game.get_room_by_id(room_id).room_name})
	moves = AvatarRules.rank(game, moves, ["nearest"], destination)
	if not AvatarRules.choose(game, frame, "next_room", moves, "Avatar movement · choose the next step toward " + game.get_room_by_id(destination).room_name, "movement_destination"): return false
	if frame.next_room == null: return _done(frame)
	var next: String = str(frame.next_room)
	frame.erase("next_room")
	frame["remaining"] = int(frame.remaining) - 1
	if not game.move_mage_to_room_id(actor, next, 1): return _done(frame)
	return false

static func _activate_room(game, frame: Dictionary) -> bool:
	var actor: int = game.avatar.player_index
	var room_id: String = str(frame.context.get("target_room_id", game.players[actor].mage.room_id))
	if not bool(frame.get("activated", false)):
		var room = game.get_room_by_id(room_id)
		if room == null or not room.can_activate(): return _done(frame)
		frame["activated"] = true
		game.activate_room(actor, room_id, false, {"avatar_no_room_effect": true})
		return false
	match str(frame.effect.reward):
		"power": game.add_player_power(actor, int(frame.effect.amount))
		"quest":
			var quest: QuestState = game.quest_manager.draw_quest(game, actor)
			if quest != null:
				game.players[actor].active_quests.erase(quest)
				quest.complete()
				game.players[actor].completed_quests.append(quest)
				game.quest_manager.solve_quest(game, actor, quest)
		"cadavers":
			var count: int = int(frame.get("summoned", 0))
			if count >= 2: return _done(frame)
			var ev: EvocationState = game.summon_evocation_for_effect(actor, "cadaver", room_id, frame)
			if game.waiting_for_player_input: return false
			if ev == null: return _done(frame)
			frame["summoned"] = count + 1
			return false
	return _done(frame)

static func _activate_evocation(game, frame: Dictionary) -> bool:
	var options: Array = []
	for ev in game.players[game.avatar.player_index].evocations:
		if ev.assigned_mage < 0 and ev.evocation_id == str(frame.effect.evocation_id) and ForgottenEvocations.can_activate(game, ev):
			options.append({"token": "evocation:%d" % ev.get_instance_id(), "value": ev, "name": ev.get_display_name()})
	if not AvatarRules.choose(game, frame, "evocation", options, "Choose an Evocation to activate."): return false
	if frame.evocation == null: return _done(frame)
	_done(frame)
	game.activate_evocation(frame.evocation, game.avatar.player_index)
	return true
