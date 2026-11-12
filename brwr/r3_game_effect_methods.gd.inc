# ---------------------------------------------------------------------------
# BRWR AI-only R3 training telemetry (not part of the production rules engine).
# Changes here are read-only observation of authoritative game state.
# A cast with no material outcome receives NO receipt.
# ---------------------------------------------------------------------------
func _brwr_r3_card_ids(cards: Array) -> Array:
	var result: Array = []
	for card in cards:
		result.append(str(card.id) if card != null else "")
	return result

func _brwr_r3_snapshot() -> Dictionary:
	var state: Dictionary = {"players": [], "rooms": [], "room_activations": _brwr_r3_room_activations}
	for player in players:
		if player == null or player.mage == null:
			continue
		var mage = player.mage
		var jinxes: Array = []
		for jinx in mage.jinxes:
			jinxes.append(str(jinx.get("id", "")))
		var quests: Array = []
		for quest in player.active_quests + player.completed_quests:
			if quest != null:
				quests.append([quest.get_id(), quest.progress, quest.completed, quest.solved])
		var evocations: Array = []
		for ev in player.evocations:
			if ev != null:
				evocations.append([ev.evocation_id, ev.board_number, ev.room_id,
					ev.damage_cubes.duplicate(), ev.health, ev.strength, ev.speed,
					ev.controller_id, ev.stored_trophies.duplicate(), ev.upgrades.duplicate()])
		state["players"].append({
			"player": player.player_index,
			"power": player.power,
			"damage": mage.damage_cubes.duplicate(),
			"destiny": mage.destiny_tokens.duplicate(),
			"infectio": mage.infectio_tokens.duplicate(),
			"jinxes": jinxes,
			"room": mage.room_id,
			"in_cell": mage.in_cell,
			"available_cubes": player.available_cubes,
			"starved_cubes": player.starved_cubes,
			"trophies": player.trophies.duplicate(),
			"hand": _brwr_r3_card_ids(player.hand),
			"grimoire": _brwr_r3_card_ids(player.grimoire),
			"memories": _brwr_r3_card_ids(player.memories),
			"quests": quests,
			"evocations": evocations
		})
	for node in get_children():
		if not node.has_meta("room_id"):
			continue
		state["rooms"].append({
			"id": str(node.get_meta("room_id")),
			"instability": node.instability_cubes.duplicate(),
			"flipped": node.flipped,
			"activated": node.activated_this_turn,
			"vastum": node.vastum_present
		})
	return state

func _brwr_r3_emit(frame: Dictionary, context: Dictionary, triggered: bool) -> void:
	if bool(frame.get("_brwr_r3_reported", false)):
		return
	frame["_brwr_r3_reported"] = true
	if not frame.has("_brwr_r3_before"):
		return
	var before: Dictionary = frame["_brwr_r3_before"]
	var after: Dictionary = _brwr_r3_snapshot()
	var material_change: bool = before != after
	# Prevention can have a real, attributable consequence without a state delta:
	# an incoming damage event is reduced before damage is committed.
	var prevention: bool = int(context.get("silver_damage_ignored", 0)) > 0 \
		or context.has("caput_ignored_player_index")
	if not material_change and not prevention:
		return
	var player: int = int(context.get("caster_id", -1))
	var step: int = int(context.get("_brwr_r3_cast_decision", -1))
	if player < 0 or player >= players.size() or step <= 0:
		_brwr_r3_uncredited += 1
		return
	var spell_type: String = str(context.get("spell_type", ""))
	var reaction: bool = triggered and spell_type in ["trap", "protection"]
	_brwr_r3_effect_events.append({
		"step": step,
		"player_index": player,
		"spell_id": str(context.get("spell_id", "")),
		"spell_type": spell_type,
		"kind": "reaction" if reaction else "spell",
		"material_change": material_change,
		"prevention": prevention
	})
