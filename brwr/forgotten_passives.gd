class_name ForgottenPassives
extends RefCounted

static func value(player, key: String) -> int:
	var result: int = 0
	for active in player.active_spells:
		if active.active:
			result += int(active.get_side().get("passives", {}).get(key, 0))
	return result

static func protects_from_spell(game, caster: int, target: int) -> bool:
	if caster == target or target < 0:
		return false
	for active in game.players[target].active_spells:
		if active.active and bool(active.get_side().get("passives", {}).get("ignore_other_spells", false)):
			return true
	return false

static func spell_room_in_range(game, caster: int, room: String, distance) -> bool:
	if game.is_room_within_effect_range(game.players[caster].mage.room_id, room, distance): return true
	if distance == null or str(distance) == "*" or int(distance) < 1 or value(game.players[caster], "demon_rooms_range_one") == 0: return false
	return ForgottenEvocations.all_models(game).any(func(ev): return ev.archetype == "demon" and ev.room_id == room and not ev.is_defeated())

static func prepare_context(game, context: Dictionary) -> void:
	if str(context.get("resolver_kind", "spell")) != "spell":
		return
	var ignored: Array = context.get("ignored_spell_players", [])
	for i in game.players.size():
		if protects_from_spell(game, int(context.get("caster_id", -1)), i) and not i in ignored:
			ignored.append(i)
	context["ignored_spell_players"] = ignored

static func source_kind(game) -> String:
	if not game.active_effect_context.is_empty():
		return str(game.active_effect_context.get("resolver_kind", "spell"))
	for frame in game.resolution_stack:
		match str(frame.get("type", "")):
			"quest_resolution": return "quest"
			"event_sequence", "event_effect": return "event"
	return ""

static func context_for(game, active: ActiveSpellState) -> Dictionary:
	return {"game": game, "caster_id": active.owner_id, "target_player_index": active.target_player_index,
		"target_model_type": "mage", "spell_target_type": "mage", "spell_forgotten": true,
		"resolver_kind": "spell", "spell_id": active.spell.id, "caster_room_id": game.players[active.owner_id].mage.room_id}

static func on_event(game, event: GameEvent) -> void:
	if event.event_type == "damage_about_to_be_inflicted":
		if event.source_model_type == "mage" and event.source_player_index >= 0:
			event.amount += value(game.players[event.source_player_index], "damage_bonus")
			if event.action_type == "spell": event.amount += value(game.players[event.source_player_index], "spell_damage_bonus")
		if event.target_model_type == "mage" and event.target_player_index >= 0:
			event.amount = maxi(0, event.amount - value(game.players[event.target_player_index], "damage_reduction"))
			if event.action_type == "spell": event.amount = maxi(0, event.amount - value(game.players[event.target_player_index], "spell_damage_reduction"))
			if event.action_type == "spell" and protects_from_spell(game, event.source_player_index, event.target_player_index):
				event.amount = 0
		if event.target_evocation != null:
			var ev: EvocationState = event.target_evocation
			if not ForgottenEvocations.ability(game, ev, "immune_damage").is_empty() or (event.action_type == "spell" and not ForgottenEvocations.ability(game, ev, "ignore_spell_effects").is_empty()):
				event.amount = 0
			for item in game.get_evocation_abilities(ev):
				if item.type == "reduce_incoming_damage":
					event.amount = maxi(0, event.amount - int(item.amount))
				elif item.type == "cap_incoming_damage":
					event.amount = mini(event.amount, int(item.amount))
	for player in game.players:
		for active in player.active_spells.duplicate():
			if not active.active:
				continue
			var data: Dictionary = active.get_side().get("passives", {})
			if data.is_empty():
				continue
			var context := context_for(game, active)
			var owner: int = active.owner_id
			var marked: int = active.target_player_index
			if event.event_type == "power_gained" and event.source_player_index == marked and str(event.data.get("source_kind", "")) in data.get("bond_power_sources", []):
				ForgottenRules.queue(game, [{"type": "gain_power", "amount": event.amount}], context)
			if event.event_type == "damage_inflicted" and event.source_model_type == "mage" and event.source_player_index == marked and bool(data.get("reflect_marked_damage", false)):
				ForgottenRules.queue(game, [{"type": "damage", "amount": event.amount}], context)
			if event.event_type == "instability_placed" and event.source_player_index == marked and bool(data.get("copy_marked_instability", false)):
				ForgottenRules.queue(game, [{"type": "self_room_effect", "effects": [{"type": "place_instability", "amount": event.amount}]}], context)
			if event.event_type == "instability_placed" and event.source_player_index == owner and bool(data.get("instability_for_black_rose_damage", false)) and not bool(event.data.get("no_instability_echo", false)):
				ForgottenRules.queue(game, [{"type": "instability_for_damage"}], context)
			if event.event_type == "spell_effect_resolved" and event.source_player_index == marked and data.has("after_marked_spell"):
				ForgottenRules.queue(game, data.after_marked_spell, context)
			if event.event_type == "mage_enters_room" and event.source_player_index == owner and data.has("on_room_entry"):
				ForgottenRules.queue(game, data.on_room_entry, context)

static func physical_attack(game, caster: int) -> void:
	if caster < 0:
		return
	for active in game.players[caster].active_spells:
		if active.active:
			var effects: Array = active.get_side().get("passives", {}).get("on_physical_attack", [])
			if not effects.is_empty():
				ForgottenRules.queue(game, effects, context_for(game, active))

static func activation_start(game, player: int) -> void:
	for ev in ForgottenEvocations.all_models(game):
		if game.get_evocation_controller_id(ev) == player and not ForgottenEvocations.ability(game, ev, "owner_activation_power").is_empty():
			game.add_player_power(player, int(ForgottenEvocations.ability(game, ev, "owner_activation_power").amount))
