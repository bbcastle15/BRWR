class_name AnubisRules
extends RefCounted

# Last Dynasty pp.8-9. All effects share the normal resolution stack, damage
# pipeline, Jinx deck and PlayerState; there is no second Avatar state.
static func active(game) -> bool:
	return game.avatar != null and game.avatar.definition.id == "anubis"

static func queue(game, effect: Dictionary, context: Dictionary = {}) -> void:
	game.queue_resolution({"type": "anubis_effect", "effect": effect, "context": context})

static func on_trophy(game, owner: int) -> void:
	if active(game) and owner == game.avatar.player_index:
		queue(game, {"type": "anubis_pledge"})

static func cannot_summon(game, owner: int, evocation_id: String) -> bool:
	if not active(game) or owner != game.avatar.player_index: return false
	if game.get_available_evocation_copies(evocation_id) > 0 and game.players[owner].has_free_evocation_slot(): return false
	queue(game, {"type": "anubis_sandstorm"})
	return true

static func resolve(game, frame: Dictionary) -> bool:
	if frame.get("done", false): return true
	var effect: Dictionary = frame.effect
	var context: Dictionary = frame.context
	var actor: int = game.avatar.player_index
	var mage: MageState = game.players[actor].mage
	var target: int = AvatarEffects._valid_target(game, context)
	var amount: int = int(effect.get("amount", 1))
	var room_id: String = str(context.get("target_room_id", mage.room_id))
	match str(effect.type):
		"anubis_pledge":
			if not frame.has("healing"):
				frame.healing = {"effect": {}, "context": {}}
			if not AvatarEffects._heal(game, frame.healing, 2): return false
			# The Avatar occupies one of the participating seats (core p.36).
			# Repeated trophies of the same Mage count, not distinct owners.
			if game.players[actor].trophies.size() >= game.players.size():
				game.players[actor].trophies.clear()
				game.add_player_power(actor, 1)
				game.append_public_log("Anubis · Judgment: gains 1 Power and returns all held Trophies.")
		"anubis_jinx":
			if target >= 0:
				if not frame.has("assignment"): frame.assignment = context.duplicate(false)
				if not ForgottenAttachments.assign_jinx(game, actor, target, frame.assignment): return false
		"anubis_convert_per_jinx":
			if target >= 0: AvatarEffects.rightmost_conversion(game, game.players[target].mage.damage_cubes, amount * game.players[target].mage.jinxes.size())
		"anubis_damage_per_jinx":
			return AvatarEffects._damage_targets(game, frame, [{"value": {"player_index": target}}] if target >= 0 else [], amount * game.players[target].mage.jinxes.size() if target >= 0 else 0)
		"anubis_instability_per_jinx":
			if target >= 0: game.place_instability(actor, game.players[target].mage.room_id, amount * game.players[target].mage.jinxes.size())
		"anubis_target_power":
			if target >= 0: game.add_player_power(target, amount)
		"anubis_steal_power", "anubis_steal_per_jinx", "anubis_steal_missing_conversion":
			if target >= 0:
				if effect.type == "anubis_steal_per_jinx": amount *= game.players[target].mage.jinxes.size()
				if effect.type == "anubis_steal_missing_conversion": amount *= maxi(0, int(context.get("conversion_requested", 0)) - int(context.get("last_converted", 0)))
				amount = mini(amount, game.players[target].power)
				game.add_player_power(target, -amount)
				game.add_player_power(actor, amount)
		"anubis_convert_instability":
			var room = game.get_room_by_id(room_id)
			var converted: int = AvatarEffects.rightmost_conversion(game, room.instability_cubes, amount, room) if room != null else 0
			game.add_player_power(actor, (amount - converted) * int(effect.get("power_per_missing", 0)))
		"anubis_instability":
			if effect.get("at", "") == "self": room_id = mage.room_id
			var placed: int = game.place_instability(actor, room_id, amount) if not mage.in_cell or effect.get("at", "") != "self" else 0
			game.add_player_power(actor, (amount - placed) * int(effect.get("power_per_missing", 0)))
		"anubis_solve_quests":
			var count: int = int(frame.get("count", 0))
			if count >= amount: return AvatarEffects._done(frame)
			frame.count = count + 1
			var quest: QuestState = game.quest_manager.draw_quest(game, actor)
			if quest != null:
				game.players[actor].active_quests.erase(quest)
				quest.complete()
				game.players[actor].completed_quests.append(quest)
				game.quest_manager.solve_quest(game, actor, quest)
			return false
		"anubis_damage_quest_mages":
			var options: Array = AvatarRules.model_options(game).filter(func(o): return not game.players[int(o.value.player_index)].completed_quests.is_empty())
			return AvatarEffects._damage_targets(game, frame, options, amount)
		"anubis_discard_solved_quest", "anubis_steal_solved_quest":
			return _quest(game, frame, target, effect.type == "anubis_steal_solved_quest")
		"anubis_steal_each_quest":
			if not frame.has("targets"): frame.targets = AvatarRules.model_options(game).map(func(o): return int(o.value.player_index))
			if frame.targets.is_empty(): return AvatarEffects._done(frame)
			if not frame.has("child"): frame.child = {}
			if not _quest(game, frame.child, int(frame.targets[0]), true): return false
			frame.targets.pop_front()
			frame.erase("child")
			return false
		"anubis_event": game.draw_event(actor, {}, game.current_moon)
		"anubis_defeat":
			AvatarEffects._done(frame)
			if target >= 0:
				game.queue_resolution({"type": "damage", "step": "after_post_event", "forced_defeat": true, "attacker_id": actor, "target_player_index": target, "action_type": "spell", "source_model_type": "mage", "no_defeat_power": true, "actual_damage": 0})
			return true
		"anubis_power_per_evocation": game.add_player_power(actor, game.players[actor].evocations.size())
		"anubis_summon": return _summon(game, frame)
		"anubis_ability":
			if not frame.has("summon"):
				frame.summon = {"effect": {"type": "anubis_summon", "at": "self"}, "context": context}
			if not _summon(game, frame.summon): return false
			var origin: String = game.players[target].mage.room_id if target >= 0 else room_id
			var options: Array = []
			for ev in game.players[actor].evocations:
				if ev.assigned_mage < 0 and AvatarRules.distance(game, origin, ev.room_id) <= 1 and ForgottenEvocations.can_activate(game, ev):
					options.append({"token": "evocation:%d" % ev.get_instance_id(), "value": ev, "name": ev.get_display_name()})
			if not AvatarRules.choose(game, frame, "evocation", options, "Anubis: activate an Evocation within 1 of the target."): return false
			AvatarEffects._done(frame)
			if frame.evocation != null: game.activate_evocation(frame.evocation, actor)
			return true
		"anubis_sandstorm":
			if not frame.has("rooms"):
				frame.rooms = []
				for ev in game.players[actor].evocations:
					if ev.assigned_mage < 0 and game.is_lodge_room_id(ev.room_id): frame.rooms.append(ev.room_id)
				game.append_public_log("Anubis · Divine Sandstorm: failed summon; inflicts 2 Damage in each owned Evocation's Room.")
			if frame.rooms.is_empty(): return AvatarEffects._done(frame)
			if not frame.has("child"): frame.child = {"context": context.duplicate(false)}
			if not AvatarEffects._damage_targets(game, frame.child, AvatarRules.model_options(game, 0, str(frame.rooms[0]), false), 2): return false
			frame.rooms.pop_front()
			frame.erase("child")
			return false
		_: push_error("Unknown Anubis effect: " + str(effect.type))
	return AvatarEffects._done(frame)

static func _quest(game, frame: Dictionary, target: int, steal: bool) -> bool:
	if frame.get("done", false): return true
	if target < 0: return AvatarEffects._done(frame)
	var options: Array = []
	for quest in game.players[target].completed_quests:
		if quest.is_solved(): options.append({"token": "quest:%d" % quest.get_instance_id(), "value": quest, "name": quest.get_name()})
	if options.is_empty(): return AvatarEffects._done(frame)
	if not AvatarEffects._human_choice(game, target, frame, "quest", options, "Anubis: choose a Solved Quest to %s." % ("give to Anubis" if steal else "discard")): return false
	var quest: QuestState = frame.quest
	if steal:
		game.players[target].completed_quests.erase(quest)
		game.players[game.avatar.player_index].completed_quests.append(quest)
	else: game.quest_manager.discard_completed_quest(game, target, quest)
	game.append_public_log("Anubis %s %s from Player %d." % ["steals" if steal else "discards", quest.get_name(), target + 1])
	return AvatarEffects._done(frame)

static func _summon(game, frame: Dictionary) -> bool:
	if frame.get("done", false): return true
	var actor: int = game.avatar.player_index
	var context: Dictionary = frame.context
	var effect: Dictionary = frame.effect
	if not frame.has("summoned"):
		var room_id: String = str(context.get("target_room_id", game.players[actor].mage.room_id))
		if effect.get("at", "") == "self": room_id = game.players[actor].mage.room_id
		if effect.get("at", "") == "black_rose": room_id = str(game.avatar.definition.setup_room)
		if effect.get("at", "") == "target":
			var target: int = AvatarEffects._valid_target(game, context)
			if target < 0: return AvatarEffects._done(frame)
			var options: Array = AvatarRules.room_options(game, int(effect.get("range", 0)), game.players[target].mage.room_id)
			if effect.get("exclude_previous", false): options = options.filter(func(o): return o.value != context.get("last_summon_room", ""))
			if not AvatarRules.choose(game, frame, "room", options, "Anubis: choose a Room for the Pharaoh.", "room_target"): return false
			if frame.room == null: return AvatarEffects._done(frame)
			room_id = str(frame.room)
		context.last_summon_room = room_id
		frame.summoned = true
		frame.evocation = game.summon_evocation_for_effect(actor, "pharaoh", room_id, frame)
		return false
	AvatarEffects._done(frame)
	if effect.get("activate", false) and frame.get("evocation") != null: game.activate_evocation(frame.evocation, actor)
	return true
