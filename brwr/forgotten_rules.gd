class_name ForgottenRules
extends RefCounted

# Codex Arcanum pp.63–67. Choices and nested sentences share the existing
# resolution stack; only card/attachment state survives outside a resolution.
const EFFECT_TYPES := ["independent_target", "self_room_effect", "target_mage_room_effect",
	"optional_effect", "place_mage_in_cell", "discard_trophies", "remove_evocation_group",
	"remove_evocation_for_power", "draw_and_finish_quest", "power_per_mage_in_cell",
	"power_by_mage_ranking", "heal_self_damage_target", "pull_model_to_target_room",
	"pull_model_to_source_room", "place_target_with_caster", "defeat_models",
	"convert_all_damage", "prevent_defeat", "damage_then_steal_survivors",
	"convert_each_model_in_self_room", "convert_each_room_near_self", "distribute_instability",
	"instability_for_damage", "assign_jinx", "assign_upgrade", "damage_per_jinx",
	"damage_per_jinxed_mage", "assign_nightmare", "activate_assigned_nightmares",
	"place_evocation_in_any_room", "heal_source_evocation", "damage_source_evocation",
	"activation_strength_bonus", "instability_cost", "instability_per_event", "activate_source_room"]

static func origin(game, context: Dictionary) -> String:
	var source: EvocationState = context.get("source_evocation")
	return source.room_id if source != null else game.players[int(context.caster_id)].mage.room_id

static func rooms(game, context: Dictionary, distance = "*") -> Array:
	return game._quest_room_choice_options(int(context.caster_id), {"range": distance}, origin(game, context))

static func models(game, context: Dictionary, kind: String = "model", distance = "*", center: String = "", include_owned: bool = true) -> Array:
	var result: Array = []
	var caster: int = int(context.caster_id)
	if center.is_empty():
		center = origin(game, context)
	for i in game.players.size():
		var p = game.players[i]
		if kind != "evocation" and i != caster and not p.mage.in_cell and game.is_room_within_effect_range(center, p.mage.room_id, distance):
			result.append({"token": "mage:%d" % i, "value": {"target_type": "mage", "player_index": i}, "player_index": i, "room_id": p.mage.room_id, "name": p.player_name})
		if kind == "mage":
			continue
		for ev in p.evocations:
			if not ev.is_defeated() and (include_owned or game.get_evocation_controller_id(ev) != caster) and game.is_room_within_effect_range(center, ev.room_id, distance):
				result.append({"token": "evocation:%d:%d" % [i, p.evocations.find(ev)], "value": {"target_type": "evocation", "evocation": ev}, "room_id": ev.room_id, "name": ev.get_display_name()})
	return result

static func target_context(context: Dictionary, value) -> Dictionary:
	var nested := DruidicRules.scoped_context(context)
	if value is String:
		nested.merge({"spell_target_type": "room", "target_room_id": value}, true)
	elif value is Dictionary:
		nested["spell_target_type"] = str(value.get("target_type", "mage"))
		nested["target_model_type"] = nested.spell_target_type
		if nested.spell_target_type == "evocation":
			nested["target_evocation"] = value.evocation
		else:
			nested["target_player_index"] = int(value.player_index)
	return nested

static func queue(game, effects: Array, context: Dictionary) -> bool:
	return DruidicRules.sequence(game, effects, context, str(context.get("resolver_kind", "spell")))

static func resolve(effect: Dictionary, context: Dictionary) -> bool:
	var game = context.get("game")
	if game == null:
		return false
	var caster: int = int(context.get("caster_id", -1))
	if caster < 0 or caster >= game.players.size():
		return false
	var player = game.players[caster]
	var target: int = int(context.get("target_player_index", -1))
	var source: EvocationState = context.get("source_evocation")
	match str(effect.type):
		"independent_target":
			var kind: String = str(effect.target)
			var options: Array = rooms(game, context, effect.get("range", "*")) if kind == "room" else models(game, context, kind, effect.get("range", "*"))
			if not DruidicRules.choose(game, caster, context, "forgotten_target", options, "Choose a " + kind + ".", bool(effect.get("optional", false)), "secondary_room" if kind == "room" else "model_target"):
				return false
			var selected = context.get("forgotten_target")
			context.erase("forgotten_target")
			if selected != null:
				return queue(game, effect.effects, target_context(context, selected))
			return true
		"self_room_effect", "target_mage_room_effect":
			var room_id: String = origin(game, context)
			if effect.type == "target_mage_room_effect":
				if target < 0 or player.mage == null or game.players[target].mage.in_cell:
					return true
				room_id = game.players[target].mage.room_id
			return queue(game, effect.effects, target_context(context, room_id))
		"optional_effect":
			if not DruidicRules.choose(game, caster, context, "forgotten_optional", [{"token": "use", "value": true, "name": "Use"}], str(effect.get("prompt", "Use this optional Effect?")), true):
				return false
			var use: bool = context.get("forgotten_optional") == true
			context.erase("forgotten_optional")
			return queue(game, effect.effects, context.duplicate(false)) if use else true
		"place_mage_in_cell":
			if target >= 0 and not DeathEffectResolver.ignores(context, target):
				game.place_mage_in_cell(target)
			return true
		"discard_trophies":
			if target >= 0:
				game.players[target].trophies.clear()
			return true
		"remove_evocation_group":
			for ev in ForgottenEvocations.all_models(game).duplicate():
				if bool(effect.get("owned_only", false)) and ev.owner_id != caster:
					continue
				if bool(effect.get("exclude_owned", false)) and ev.owner_id == caster:
					continue
				if effect.get("scope") == "target_room" and ev.room_id != str(context.get("target_room_id", "")):
					continue
				if effect.has("evocation_id") and ev.evocation_id != str(effect.evocation_id):
					continue
				if bool(effect.get("non_forgotten", false)) and bool(game.evocation_database.get_evocation(ev.evocation_id).get("forgotten", false)):
					continue
				game.effect_resolver._remove_evocation(game, ev, context, false)
			return true
		"remove_evocation_for_power":
			var options := models(game, context, "evocation")
			if not DruidicRules.choose(game, caster, context, "forgotten_remove", options, "Choose an Evocation to remove.", false, "evocation_target"):
				return false
			var selected = context.get("forgotten_remove")
			context.erase("forgotten_remove")
			if selected is Dictionary and game.effect_resolver._remove_evocation(game, selected.evocation, context, false):
				game.add_player_power(caster, int(effect.amount))
			return true
		"draw_and_finish_quest":
			var quest = game.quest_manager.draw_quest(game, caster, int(effect.moon))
			if quest != null:
				game.quest_manager.complete_active_quest(game, caster, quest)
				if bool(effect.get("solve", false)):
					game.quest_manager.solve_quest(game, caster, quest, {})
			return true
		"power_per_mage_in_cell":
			var count: int = 0
			for p in game.players:
				if p.mage.in_cell:
					count += 1
			game.add_player_power(caster, mini(count * int(effect.amount), int(effect.max)))
			return true
		"power_by_mage_ranking":
			var baseline: int = player.power
			for i in game.players.size():
				if i == caster or game.players[i].mage.in_cell:
					continue
				if game.players[i].power > baseline:
					queue(game, [{"type": "steal_power", "amount": 1}], DeathEffectResolver.mage_context(context, i))
				elif game.players[i].power < baseline:
					game.add_player_power(caster, 1)
			return true
		"heal_self_damage_target":
			game.effect_resolver._resolve_heal_all_damage({}, context)
			return queue(game, [{"type": "damage", "amount": int(context.get("effect_damage_healed", 0))}], context)
		"pull_model_to_target_room", "pull_model_to_source_room":
			var room_id: String = origin(game, context) if effect.type == "pull_model_to_source_room" else str(context.get("target_room_id", ""))
			var options := models(game, context, str(effect.get("target", "model")), effect.get("distance", 1), room_id)
			if not DruidicRules.choose(game, caster, context, "forgotten_pull", options, "Choose a Model to place in the Room.", bool(effect.get("optional", false)), "model_target"):
				return false
			var selected = context.get("forgotten_pull")
			context.erase("forgotten_pull")
			if selected is Dictionary:
				game.effect_resolver._place_target_model_direct(game, target_context(context, selected), room_id)
			return true
		"place_target_with_caster":
			game.effect_resolver._place_target_model_direct(game, context, origin(game, context))
			return true
		"defeat_models":
			return game.queue_resolution({"type": "forgotten_defeat", "effect": effect, "context": context.duplicate(false), "index": 0})
		"convert_all_damage":
			var amount: int = game.players[target].mage.get_damage() if target >= 0 else 0
			return queue(game, [{"type": "convert_damage", "amount": amount}], context)
		"prevent_defeat":
			for frame in game.resolution_stack:
				if frame.get("type") == "damage" and int(frame.get("target_player_index", -1)) == caster:
					frame["forced_defeat"] = false
			return true
		"damage_then_steal_survivors":
			return game.queue_resolution({"type": "forgotten_survivors", "context": context, "effect": effect})
		"convert_each_model_in_self_room":
			for option in models(game, context, "model", 0):
				queue(game, [{"type": "convert_damage", "amount": int(effect.amount)}], target_context(context, option.value))
			return true
		"convert_each_room_near_self":
			for option in rooms(game, context, effect.distance):
				queue(game, [{"type": "convert_instability", "amount": int(effect.amount)}], target_context(context, option.value))
			return true
		"distribute_instability":
			return game.queue_resolution({"type": "forgotten_distribute", "context": context, "remaining": int(effect.amount), "minimum": int(effect.min_rooms), "placements": {}})
		"instability_for_damage":
			var options: Array = []
			for n in range(0, mini(game.get_node("EventBoard").black_rose_cube_count, player.mage.get_remaining_health()) + 1):
				options.append({"token": "amount:%d" % n, "value": n, "name": "%d Damage / Instability" % n})
			if not DruidicRules.choose(game, caster, context, "forgotten_amount", options, "Choose Black Rose Damage to suffer."):
				return false
			var amount: int = int(context.get("forgotten_amount", 0))
			context.erase("forgotten_amount")
			var nested := target_context(context, player.mage.room_id)
			nested["no_instability_echo"] = true
			queue(game, [{"type": "place_instability", "amount": amount}], nested)
			game.deal_damage(-1, caster, amount, "spell")
			return true
		"assign_jinx":
			if context.get("target_evocation") != null: return true
			return ForgottenAttachments.assign_jinx(game, caster, target, context, effect)
		"assign_upgrade":
			return ForgottenAttachments.assign_upgrade(game, caster, context.get("target_evocation", context.get("last_summoned_evocation", source)), context, effect)
		"damage_per_jinx":
			return queue(game, [{"type": "damage", "amount": game.players[target].mage.jinxes.size() * int(effect.amount)}], context) if target >= 0 else true
		"damage_per_jinxed_mage":
			var count: int = 0
			for p in game.players:
				if not p.mage.jinxes.is_empty():
					count += 1
			return queue(game, [{"type": "damage", "amount": count}], context)
		"assign_nightmare", "activate_assigned_nightmares":
			return ForgottenEvocations.resolve_assignment(game, effect, context)
		"place_evocation_in_any_room":
			if source == null:
				return true
			if not DruidicRules.choose(game, caster, context, "forgotten_place", rooms(game, context), "Place " + source.evocation_name + " in a Room.", true, "movement_destination"):
				return false
			var destination = context.get("forgotten_place")
			context.erase("forgotten_place")
			if destination is String:
				game.place_evocation_in_room_direct(source, destination)
			return true
		"heal_source_evocation":
			if source != null:
				game.effect_resolver._heal_evocation(game, source, int(effect.amount))
			return true
		"damage_source_evocation":
			if source != null:
				game.deal_damage_to_evocation(-1 if bool(effect.get("black_rose", false)) else caster, source, int(effect.amount), [], "evocation", "black_rose" if bool(effect.get("black_rose", false)) else "evocation", null if bool(effect.get("black_rose", false)) else source)
			return true
		"activation_strength_bonus":
			var frame: Dictionary = context.get("evocation_activation_frame", {})
			frame["strength_bonus"] = int(frame.get("strength_bonus", 0)) + int(effect.amount)
			return true
		"instability_cost":
			var room = game.get_room_by_id(origin(game, context))
			if room == null or room.instability_cubes.count(caster) < int(effect.amount):
				return true
			if not DruidicRules.choose(game, caster, context, "forgotten_cost", [{"token": "pay", "value": true, "name": "Remove %d of your Instability" % int(effect.amount)}], "Pay Instability for this Effect?", true):
				return false
			var pay: bool = context.get("forgotten_cost") == true
			context.erase("forgotten_cost")
			if pay:
				game.remove_player_instability(caster, room.room_id, int(effect.amount))
				return queue(game, effect.effects, context)
			return true
		"instability_per_event":
			return resolve({"type": "independent_target", "target": "room", "range": effect.get("range", 1), "effects": [{"type": "place_instability", "amount": event_count(game)}]}, context)
		"activate_source_room":
			if not DruidicRules.choose(game, caster, context, "forgotten_activate_room", [{"token": "room:" + origin(game, context), "value": true, "room_id": origin(game, context), "name": "Activate this Room"}], "Activate the Evocation's Room?", true, "secondary_room"):
				return false
			var activate: bool = context.get("forgotten_activate_room") == true
			context.erase("forgotten_activate_room")
			if activate:
				var nested := context.duplicate(false)
				nested["force_room_activation"] = true
				game.activate_room(caster, origin(game, context), true, nested)
			return true
	return false

static func event_count(game) -> int:
	var n: int = 0
	for event in game.active_events:
		if event != null:
			n += 1
	return n

static func process_frame(game, frame: Dictionary) -> bool:
	if bool(frame.get("finished", false)):
		return true
	var context: Dictionary = frame.context
	var caster: int = int(context.caster_id)
	match str(frame.type):
		"forgotten_defeat":
			var effect: Dictionary = frame.effect
			if frame.has("pending_defeat"):
				if bool(frame.pending_defeat.get("completed", false)):
					frame["defeated"] = int(frame.defeated) + 1
				frame.erase("pending_defeat")
			if not frame.has("targets"):
				var targets: Array = []
				if context.get("spell_target_type") == "mage":
					targets.append({"target_type": "mage", "player_index": int(context.get("target_player_index", -1))})
				else:
					for option in models(game, context, "mage" if bool(effect.get("mages_only", false)) else "model", effect.get("distance", 0), str(context.get("target_room_id", ""))):
						targets.append(option.value)
				frame["targets"] = targets
				frame["defeated"] = 0
			if int(frame.index) >= frame.targets.size():
				frame["finished"] = true
				game.add_player_power(caster, mini(int(frame.defeated) * int(effect.get("power_each", 0)), int(effect.get("max_power", 0))))
				return true
			var value: Dictionary = frame.targets[int(frame.index)]
			frame.index = int(frame.index) + 1
			if value.target_type == "mage":
				var victim: int = int(value.player_index)
				if victim >= 0 and not game.players[victim].mage.in_cell and not DeathEffectResolver.ignores(context, victim):
					var damage := {"type": "damage", "step": "after_post_event", "forced_defeat": true, "attacker_id": caster, "target_player_index": victim, "action_type": "spell", "source_model_type": "mage", "no_defeat_power": bool(effect.get("no_defeat_power", false)), "actual_damage": 0}
					var receipt: Dictionary = {}
					damage["defeat_receipt"] = receipt
					frame["pending_defeat"] = receipt
					game.queue_resolution(damage)
			else:
				var ev: EvocationState = value.evocation
				if ForgottenEvocations.can_remove(game, ev, context):
					game.emit_evocation_defeated_or_removed(ev, "defeated")
					game.finalize_evocation_removal(ev)
			return false
		"forgotten_survivors":
			if not frame.has("started"):
				frame["started"] = true
				frame["mages"] = []
				for i in game.players.size():
					if i != caster and not game.players[i].mage.in_cell:
						frame.mages.append(i)
				queue(game, [{"type": "damage_all_models_lodge", "amount": int(frame.effect.damage)}], context)
				return false
			frame["finished"] = true
			for i in frame.mages:
				if not game.players[i].mage.in_cell:
					queue(game, [{"type": "steal_power", "amount": int(frame.effect.power)}], DeathEffectResolver.mage_context(context, i))
			return true
		"forgotten_distribute":
			# Commit together once the four-Room minimum is satisfied.
			var available: int = mini(int(frame.remaining), game.players[caster].available_cubes - frame.placements.values().reduce(func(n, v): return n + int(v), 0))
			var options: Array = []
			for option in rooms(game, context):
				var room = game.get_room_by_id(str(option.value))
				if room != null and not room.flipped and room.instability_cubes.size() + int(frame.placements.get(option.value, 0)) < room.get_instability_resistance():
					if int(frame.remaining) <= maxi(0, int(frame.minimum) - frame.placements.size()) and frame.placements.has(option.value):
						continue
					options.append(option)
			if available <= 0 or options.is_empty() or bool(frame.get("finish", false)):
				frame["finished"] = true
				if frame.placements.size() >= int(frame.minimum):
					for room_id in frame.placements:
						game.place_player_instability(caster, room_id, int(frame.placements[room_id]))
				return true
			if not DruidicRules.choose(game, caster, frame, "room", options, "Place up to 8 Instability in at least 4 different Rooms.", frame.placements.size() >= int(frame.minimum), "secondary_room"):
				return false
			var selected = frame.get("room")
			frame.erase("room")
			if selected is String:
				frame.placements[selected] = int(frame.placements.get(selected, 0)) + 1
				frame.remaining = int(frame.remaining) - 1
			else:
				frame["finish"] = true
			return false
	return true
