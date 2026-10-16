class_name EquipmentRules
extends RefCounted

static func stat_bonus(player: PlayerState, stat: String) -> int:
	var result: int = 0
	for ev in player.evocations:
		if ev.archetype != "equipment" or ev.is_defeated(): continue
		for ability in ev.definition.get("abilities", []):
			if ability.type == "owner_stats": result += int(ability.get(stat, 0))
	return result

static func has_ability(game, player: int, kind: String) -> bool:
	for ev in game.players[player].evocations:
		if ev.archetype == "equipment" and not ev.is_defeated() and not ForgottenEvocations.ability(game, ev, kind).is_empty(): return true
	return false

static func sync(game) -> void:
	for player in game.players:
		if player.mage == null: continue
		for ev in player.evocations:
			if ev.archetype == "equipment": ev.room_id = player.mage.room_id

static func actions(game, player_index: int) -> Array:
	var player: PlayerState = game.players[player_index]
	var result: Array = []
	if player.mage.in_cell or not player.has_physical_action(): return result
	for ev in player.evocations:
		if ev.archetype != "equipment" or ev.is_defeated(): continue
		for ability in game.get_evocation_abilities(ev):
			if ability.type == "equipment_action":
				result.append({"kind": "equipment", "label": ev.evocation_name + " · " + str(ability.name),
					"action": {"type": "equipment", "evocation_id": ev.evocation_id, "action_id": ability.id}, "consumes_action": true})
	for active in player.active_spells:
		if not active.active: continue
		for action in active.get_side().get("passives", {}).get("physical_actions", []):
			result.append({"kind": "equipment", "label": str(action.name), "action": {"type": "spell_physical", "spell_id": active.spell.id, "action_id": action.id}, "consumes_action": true})
	return result

static func perform_spell_action(game, player_index: int, id: String, action_id: String) -> bool:
	var player: PlayerState = game.players[player_index]
	if player.mage.in_cell or not player.has_physical_action(): return false
	for active in player.active_spells:
		if not active.active or active.spell.id != id: continue
		for action in active.get_side().get("passives", {}).get("physical_actions", []):
			if str(action.id) != action_id: continue
			player.exhaust_physical_action()
			game.refresh_player_board(player_index)
			return game.queue_resolution({"type": "druidic_action", "player_index": player_index, "index": 0,
				"effects": action.effects, "context": {"game": game, "caster_id": player_index, "caster_room_id": player.mage.room_id, "action_type": "physical"}})
	return false

static func perform(game, player_index: int, id: String, action: String) -> bool:
	var player: PlayerState = game.players[player_index]
	if player.mage.in_cell or not player.has_physical_action(): return false
	for ev in player.evocations:
		if ev.evocation_id != id or ev.is_defeated(): continue
		for ability in game.get_evocation_abilities(ev):
			if ability.type != "equipment_action" or ability.id != action: continue
			player.exhaust_physical_action()
			game.refresh_player_board(player_index)
			return game.queue_resolution({"type": "druidic_action", "player_index": player_index, "index": 0,
				"effects": ability.effects, "context": {"game": game, "caster_id": player_index,
					"caster_room_id": player.mage.room_id, "action_type": "physical_attack"}})
	return false

static func on_event(game, event: GameEvent) -> void:
	if event.event_type == "mage_placed_in_cell":
		for equipment in ForgottenEvocations.all_models(game).duplicate():
			var ability := ForgottenEvocations.ability(game, equipment, "collect_trophy_on_cell")
			if ability.is_empty(): continue
			equipment.stored_trophies.append(equipment.owner_id)
			if equipment.stored_trophies.size() >= int(ability.threshold):
				equipment.stored_trophies.clear()
				game.emit_evocation_defeated_or_removed(equipment, "removed")
				game.finalize_evocation_removal(equipment)
				game.add_player_power(equipment.owner_id, int(ability.power))
		for ev in game.players[event.source_player_index].evocations.duplicate():
			if ev.archetype == "equipment":
				# Equipment is assigned to this Mage; unlike ordinary summons it
				# leaves play when its owner is defeated (rulebook p.28).
				game.emit_evocation_defeated_or_removed(ev, "removed")
				game.finalize_evocation_removal(ev)
	if event.event_type == "damage_inflicted" and event.amount > 0 and event.source_model_type == "mage" and event.action_type == "physical_attack":
		var owner: int = event.source_player_index
		if owner >= 0 and has_ability(game, owner, "convert_after_owner_attack"):
			var context := {"game": game, "caster_id": owner, "resolver_kind": "evocation", "trigger_event": event}
			ForgottenRules.queue(game, [{"type": "optional_effect", "effects": [{"type": "trigger_target_effect", "effects": [{"type": "convert_damage", "amount": 2}]}]}], context)
	if event.event_type == "evocation_defeated_or_removed" and event.target_evocation != null:
		var ev: EvocationState = event.target_evocation
		if ev.archetype == "equipment" and event.action_type in ["removed", "defeated"]:
			var ability := ForgottenEvocations.ability(game, ev, "instability_on_removal")
			if not ability.is_empty():
				ForgottenRules.queue(game, [{"type": "place_instability", "amount": int(ability.amount)}],
					{"game": game, "caster_id": ev.owner_id, "resolver_kind": "evocation", "spell_target_type": "room", "target_room_id": ev.room_id})
