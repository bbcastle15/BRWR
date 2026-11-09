# BRWR AI v1: permission-filtered observation + selectable legal decisions.
# No rules are implemented here: all actions go through Game.submit_beta_input().
extends RefCounted

const NetworkProjectionScript = preload("res://network_projection.gd")

var _game
# Multi-step private choices. A partial choice never mutates Game.
var _stages: Dictionary = {}

func _init(game_node: Node) -> void:
	_game = game_node


func observation(player_index: int) -> Dictionary:
	if not _valid_player(player_index):
		return {}
	# Reuse the same owner-filtered projection as online multiplayer.
	return _json_safe(NetworkProjectionScript.build(_game, player_index))


func result() -> Dictionary:
	return {
		"done": bool(_game.game_has_ended),
		"result": _json_safe(_game.final_result) if _game.game_has_ended else {}
	}


func decision(player_index: int) -> Dictionary:
	if not _valid_player(player_index) or _game.game_has_ended:
		return {}
	if not _game.waiting_for_player_input:
		return {}
	var request: Dictionary = _game.get_beta_pending_input(player_index)
	if int(request.get("player_index", -1)) != player_index:
		return {}
	if bool(request.get("private", false)):
		return {}
	var stage: Dictionary = _stage_for(player_index, request)
	var candidates: Array = _stage_candidates(stage) if not stage.is_empty() else _enumerate(player_index, request)
	return {
		"player_index": player_index,
		"type": str(request.get("type", "")),
		"substep": str(stage.get("phase", "")),
		"revision": int(_game.input_revision),
		"signature": _stage_signature(request, stage),
		"candidates": candidates,
		"supported": not candidates.is_empty()
	}


func step(player_index: int, choice_id: int, signature: String) -> bool:
	# The caller supplies only an index from our current candidate list.
	if not _valid_player(player_index) or _game.game_has_ended:
		return false
	if _game.network_client or _game.network_session != null:
		return false # Offline training only.
	var fresh: Dictionary = decision(player_index)
	if fresh.is_empty():
		_debug_rejection("no_current_decision", player_index, choice_id, {}, {}, {})
		return false
	if str(fresh.get("signature", "")) != signature:
		_debug_rejection("signature_changed", player_index, choice_id, fresh, {}, {})
		return false
	var candidates: Array = fresh.get("candidates", [])
	if choice_id < 0 or choice_id >= candidates.size():
		_debug_rejection("choice_out_of_range", player_index, choice_id, fresh, {}, {})
		return false
	var candidate: Dictionary = candidates[choice_id]
	var payload: Dictionary = candidate.get("payload", {}).duplicate(true)
	var request_before: Dictionary = _game.get_beta_pending_input(player_index)
	var stage_before: Dictionary = _stages.get(player_index, {}).duplicate(true)
	var revision_before: int = int(_game.input_revision)
	var ok: bool = false
	if not stage_before.is_empty():
		ok = _advance_stage(player_index, _stages.get(player_index, {}), payload)
	else:
		ok = _game.submit_beta_input(player_index, payload)
	if not ok:
		_debug_rejection("submit_or_stage_rejected", player_index, choice_id, fresh, candidate, {
			"revision_before": revision_before,
			"request_before": _request_summary(request_before),
			"stage_before": _stage_summary(stage_before),
			"stage_after": _stage_summary(_stages.get(player_index, {}))
		})
	return ok


func _request_summary(req: Dictionary) -> Dictionary:
	var tokens: Array = []
	for item in (req.get("board_options", []) if bool(req.get("board_only", false)) else req.get("options", [])):
		if item is Dictionary:
			tokens.append(str(item.get("token", "")))
	return {
		"type": str(req.get("type", "")),
		"choice_kind": str(req.get("choice_kind", "")),
		"context_key": str(req.get("context_key", "")),
		"min_select": int(req.get("min_select", 1)),
		"max_select": int(req.get("max_select", 1)),
		"board_only": bool(req.get("board_only", false)),
		"tokens": tokens
	}


func _stage_summary(state: Dictionary) -> Dictionary:
	return {
		"kind": str(state.get("kind", "")),
		"phase": str(state.get("phase", "")),
		"selected": state.get("selected", []).duplicate(),
		"min": int(state.get("min", 0)),
		"max": int(state.get("max", 0))
	}


func _debug_rejection(reason: String, player_index: int, choice_id: int,
	current: Dictionary, candidate: Dictionary, extra: Dictionary) -> void:
	var current_request: Dictionary = _game.get_beta_pending_input(player_index)
	var runtime_tokens: Array = []
	if _game.pending_effect_choice_values is Dictionary:
		for key in _game.pending_effect_choice_values.keys():
			runtime_tokens.append(str(key))
	var report: Dictionary = {
		"reason": reason,
		"player_index": player_index,
		"choice_id": choice_id,
		"choice_label": str(candidate.get("label", "")),
		"choice_payload": candidate.get("payload", {}),
		"decision_type": str(current.get("type", "")),
		"substep": str(current.get("substep", "")),
		"waiting_after": bool(_game.waiting_for_player_input),
		"revision_after": int(_game.input_revision),
		"pending_after": _request_summary(current_request),
		"runtime_tokens_after": runtime_tokens,
		"details": extra
	}
	printerr("AI_BRIDGE_REJECT_DETAIL ", JSON.stringify(_json_safe(report)))

func _valid_player(player_index: int) -> bool:
	return _game != null and player_index >= 0 and player_index < _game.players.size()


func _signature(request: Dictionary) -> String:
	return (str(_game.input_revision) + ":" + JSON.stringify(_json_safe(request))).sha256_text()


func _add(out: Array, label: String, payload: Dictionary, detail: Dictionary = {}) -> void:
	out.append({
		"id": out.size(),
		"label": label,
		"payload": _json_safe(payload),
		"detail": _json_safe(detail)
	})


func _enumerate(player_index: int, req: Dictionary) -> Array:
	var result_actions: Array = []
	var kind := str(req.get("type", ""))
	match kind:
		"starting_mage_choice":
			for entry in req.get("available_mages", []):
				_add(result_actions, str(entry.get("name", entry.get("id", ""))),
					{"mage_id": str(entry.get("id", ""))}, entry)
		"starting_school_choice":
			for entry in req.get("available_schools", []):
				_add(result_actions, str(entry.get("name", entry.get("id", ""))),
					{"school_id": str(entry.get("id", ""))}, entry)
		"starting_grimoire_choice":
			for entry in req.get("options", []):
				_add(result_actions, str(entry.get("name", entry.get("id", ""))),
					{"grimoire_id": str(entry.get("id", ""))}, entry)
		"action_activation_step":
			for entry in req.get("options", []):
					var token := str(entry.get("token", ""))
					if token != "":
						_add(result_actions, str(entry.get("label", token)),
							{"token": token}, {"kind": entry.get("kind", ""), "descriptor": entry.get("descriptor", {}), "action": entry.get("action", {})})
		"effect_choice":
			# Single-target requests are enumerated directly. Multi-target requests
			# are selected incrementally in _stage_for (no combinatorial cap).
			var options: Array = req.get("board_options", []) if bool(req.get("board_only", false)) else req.get("options", [])
			var min_select: int = int(req.get("min_select", 1))
			var max_select: int = int(req.get("max_select", 1))
			if min_select == 0:
				_add(result_actions, "Select none", {"selection": []})
			if max_select > 0:
				for entry in options:
					if entry is Dictionary and str(entry.get("token", "")) != "":
						_add(result_actions, str(entry.get("label", entry.get("token", ""))), {"selection": str(entry.get("token"))}, entry)
		"chaos_reveal_ack":
			_add(result_actions, "Continue", {"acknowledge": true})
		"trigger_decision":
			_add(result_actions, "Pass", {"queue_index": -1})
			for entry in req.get("options", []):
				_add(result_actions, "Trigger " + str(entry.get("spell_name", "")),
					{"queue_index": int(entry.get("queue_index", -1))}, entry)
		"study_choose_schools":
			var schools: Array = req.get("active_school_ids", [])
			for a in schools:
				_add(result_actions, "Draw 4 " + str(a), {"school_ids": [a, a, a, a]})
			for a in schools:
				for b in schools:
					if a != b:
						_add(result_actions, "Draw 2 " + str(a) + ", 2 " + str(b), {"school_ids": [a, a, b, b]})
						_add(result_actions, "Draw 3 " + str(a) + ", 1 " + str(b), {"school_ids": [a, a, a, b]})
		"study_keep_cards":
			pass # Handled by incremental _stage_for().
		"study_optional_discard":
			_add(result_actions, "Keep hand", {"hand_index": -1})
			for entry in req.get("hand", []):
				_add(result_actions, "Discard " + str(entry.get("name", "")),
					{"hand_index": int(entry.get("hand_index", -1))}, entry)
		"study_hand_limit":
			pass # Handled by incremental _stage_for().
		"preparation":
			pass # Handled by incremental _stage_for().
		"evocation_phase_activations":
			for entry in req.get("evocations", []):
				for plan in entry.get("activation_plans", []):
					_add(result_actions, str(plan.get("label", "Activate")),
						{"choices": [{"evocation_index": int(entry.get("evocation_index", -1)), "context": plan.get("context", {})}]},
						{"evocation": entry.get("id", ""), "plan": plan})
		"cleanup_active_spells":
			_add(result_actions, "Return no active spells", {"return_to_hand_indices": []})
			var indices: Array = []
			for entry in req.get("active_spells", []):
				indices.append(int(entry.get("active_index", -1)))
				_add(result_actions, "Return " + str(entry.get("spell_name", "")),
						{"return_to_hand_indices": [int(entry.get("active_index", -1))]}, entry)
			if indices.size() > 1:
				_add(result_actions, "Return all active spells", {"return_to_hand_indices": indices})
		"black_rose_optional_quest_discard":
			_add(result_actions, "Keep quests", {"quest_index": -1})
			for entry in req.get("quests", []):
				_add(result_actions, "Discard quest " + str(entry.get("name", "")),
						{"quest_index": int(entry.get("quest_index", -1))}, entry)
		"black_rose_active_quest_limit", "black_rose_completed_quest_limit":
			pass # Handled by incremental _stage_for().
		"final_winner_choice":
			for entry in req.get("contenders", []):
				var index: int = int(entry.get("player_index", -1)) if entry is Dictionary else int(entry)
				_add(result_actions, "Winner " + str(index), {"winner": index})
	return result_actions


# Incremental decisions keep the public action list small, while preserving
# ALL legal Light/Dark choices and arbitrary numbers of combinatorial options.
# The authoritative game validates the full payload on completion.
func _stage_for(player_index: int, req: Dictionary) -> Dictionary:
	var kind: String = str(req.get("type", ""))
	var staged: bool = kind in ["preparation", "study_keep_cards", "study_hand_limit", "black_rose_active_quest_limit", "black_rose_completed_quest_limit"]
	if kind == "effect_choice" and int(req.get("max_select", 1)) > 1:
		staged = true
	if not staged:
		_stages.erase(player_index)
		return {}
	var key: String = _signature(req)
	var state: Dictionary = _stages.get(player_index, {})
	if str(state.get("request_key", "")) == key:
		return state
	state = {"request_key": key, "kind": kind, "phase": "pick", "selected": []}
	if kind == "preparation":
		var usable: Array = []
		for entry in req.get("hand", []):
			if not entry is Dictionary:
				continue
			var spell = _game.spell_database.get_spell(str(entry.get("id", "")))
			if spell == null:
				continue
			var light: bool = spell.is_playable_side(false)
			var dark: bool = spell.is_playable_side(true)
			if not light and not dark:
				continue
			usable.append({"index": int(entry.get("hand_index", -1)), "id": str(spell.id), "school_id": str(spell.school_id),
				"light": light, "dark": dark, "light_features": _spell_side_features(spell.get_side(false)),
				"dark_features": _spell_side_features(spell.get_side(true)), "instability": spell.has_instability()})
		state.merge({"phase": "count", "usable": usable, "ready_count": 0, "ready_indices": [], "ready_sides": [], "quick_index": -1, "quick_dark": false,
			"min_spells": int(req.get("min_spells", 2)), "max_spells": int(req.get("max_spells", 4)),
			"max_numbered": int(req.get("max_numbered_spells", 3)), "quick_allowed": bool(req.get("quick_allowed", true))}, true)
	else:
		var options: Array = []
		var key_name: String = ""
		var records: Array = []
		var minimum: int = 0
		var maximum: int = 0
		match kind:
			"effect_choice":
				key_name = "token"
				records = req.get("board_options", []) if bool(req.get("board_only", false)) else req.get("options", [])
				minimum = int(req.get("min_select", 1))
				maximum = int(req.get("max_select", 1))
			"study_keep_cards":
				key_name = "draw_index"
				records = req.get("cards", [])
				minimum = int(req.get("keep_count", 2))
				maximum = minimum
			"study_hand_limit":
				key_name = "hand_index"
				records = req.get("hand", [])
				minimum = int(req.get("discard_count", 0))
				maximum = minimum
			_:
				key_name = "quest_index"
				records = req.get("quests", [])
				minimum = int(req.get("discard_count", 0))
				maximum = minimum
		for entry in records:
			if entry is Dictionary and entry.has(key_name):
				var value: Variant = entry[key_name]
				if key_name == "token":
					value = str(value)
					if value == "":
						continue
				else:
					value = int(value)
					if value < 0:
						continue
				var present: bool = false
				for prior in options:
					if prior.get("value") == value:
						present = true
						break
				if not present:
					options.append({"value": value, "label": str(entry.get("label", entry.get("name", str(value)))), "detail": entry})
		state.merge({"options": options, "min": minimum, "max": mini(maximum, options.size())})
	_stages[player_index] = state
	return state

func _stage_signature(req: Dictionary, state: Dictionary) -> String:
	var sig: String = _signature(req)
	if state.is_empty():
		return sig
	return (sig + ":" + JSON.stringify(_json_safe(state))).sha256_text()

func _spell_side_features(side: Dictionary) -> Dictionary:
	# Generic semantic descriptors: new Schools can reuse learned effect weights.
	var effect_types: Array = []
	for effect in side.get("effects", []):
		if effect is Dictionary:
			effect_types.append(str(effect.get("type", "")))
	return {"type": str(side.get("type", "")), "target": str(side.get("target", "")),
		"range": str(side.get("range", "")), "effect_types": effect_types}

func _prep_card(state: Dictionary, hand_index: int) -> Dictionary:
	for entry in state.get("usable", []):
		if int(entry.get("index", -1)) == hand_index:
			return entry
	return {}

func _stage_candidates(state: Dictionary) -> Array:
	var result_actions: Array = []
	var phase: String = str(state.get("phase", ""))
	if str(state.get("kind", "")) != "preparation":
		var selected: Array = state.get("selected", [])
		if selected.size() >= int(state.get("min", 0)):
			_add(result_actions, "Confirm selection", {"ai_finish": true}, {"selected_count": selected.size()})
		if selected.size() >= int(state.get("max", 0)):
			return result_actions
		for item in state.get("options", []):
			if not selected.has(item.get("value")):
				_add(result_actions, "Select " + str(item.get("label", "")), {"ai_select": item.get("value")}, item.get("detail", {}))
		return result_actions
	var usable: Array = state.get("usable", [])
	match phase:
		"count":
			var low: int = maxi(1, int(state.get("min_spells", 2)) - (1 if bool(state.get("quick_allowed", true)) else 0))
			var high: int = mini(int(state.get("max_numbered", 3)), mini(int(state.get("max_spells", 4)), usable.size()))
			for n in range(low, high + 1):
				if n < int(state.get("min_spells", 2)) and (not bool(state.get("quick_allowed", true)) or usable.size() < n + 1):
					continue
				_add(result_actions, "%d numbered Spells" % n, {"ai_count": n}, {"ready_count": n})
		"ready_card", "quick_card":
			if phase == "quick_card" and state.get("ready_indices", []).size() >= int(state.get("min_spells", 2)):
				_add(result_actions, "No Quick Spell", {"ai_hand_index": -1}, {"quick": false})
			for entry in usable:
				var index: int = int(entry.get("index", -1))
				if not state.get("ready_indices", []).has(index):
					_add(result_actions, ("Quick " if phase == "quick_card" else "Ready ") + str(entry.get("id", "")), {"ai_hand_index": index}, entry)
		"ready_side", "quick_side":
			var index: int = int(state.get("quick_index", -1)) if phase == "quick_side" else int(state.get("ready_indices", []).back())
			var card: Dictionary = _prep_card(state, index)
			if bool(card.get("light", false)):
				_add(result_actions, str(card.get("id", "")) + " Light", {"ai_dark": false}, {"spell_id": card.get("id", ""), "school_id": card.get("school_id", ""), "side": "Light", "side_features": card.get("light_features", {})})
			if bool(card.get("dark", false)):
				_add(result_actions, str(card.get("id", "")) + " Dark", {"ai_dark": true}, {"spell_id": card.get("id", ""), "school_id": card.get("school_id", ""), "side": "Dark", "side_features": card.get("dark_features", {})})
	return result_actions

func _advance_stage(player_index: int, state: Dictionary, choice: Dictionary) -> bool:
	if str(state.get("kind", "")) != "preparation":
		if bool(choice.get("ai_finish", false)):
			return _commit_stage(player_index, state)
		if not choice.has("ai_select"):
			return false
		var selected: Array = state.get("selected", [])
		selected.append(choice["ai_select"])
		state["selected"] = selected
		_stages[player_index] = state
		if selected.size() >= int(state.get("max", 0)):
			return _commit_stage(player_index, state)
		return true
	match str(state.get("phase", "")):
		"count":
			state["ready_count"] = int(choice.get("ai_count", 0))
			state["phase"] = "ready_card"
		"ready_card":
			var indices: Array = state.get("ready_indices", [])
			indices.append(int(choice.get("ai_hand_index", -1)))
			state["ready_indices"] = indices
			state["phase"] = "ready_side"
		"ready_side":
			var sides: Array = state.get("ready_sides", [])
			sides.append(bool(choice.get("ai_dark", false)))
			state["ready_sides"] = sides
			if sides.size() < int(state.get("ready_count", 0)):
				state["phase"] = "ready_card"
			elif bool(state.get("quick_allowed", true)) and sides.size() + 1 <= int(state.get("max_spells", 4)):
				state["phase"] = "quick_card"
			else:
				return _commit_stage(player_index, state)
		"quick_card":
			state["quick_index"] = int(choice.get("ai_hand_index", -1))
			if int(state["quick_index"]) == -1:
				return _commit_stage(player_index, state)
			state["phase"] = "quick_side"
		"quick_side":
			state["quick_dark"] = bool(choice.get("ai_dark", false))
			return _commit_stage(player_index, state)
		_:
			return false
	_stages[player_index] = state
	return true

func _commit_stage(player_index: int, state: Dictionary) -> bool:
	var payload: Dictionary = {}
	match str(state.get("kind", "")):
		"preparation":
			payload = {"ready_hand_indices": state.get("ready_indices", []), "ready_dark_sides": state.get("ready_sides", []),
				"quick_hand_index": int(state.get("quick_index", -1)), "quick_dark_side": bool(state.get("quick_dark", false))}
		"effect_choice":
			var chosen: Array = state.get("selected", [])
			payload = {"selection": chosen if int(state.get("max", 1)) > 1 else (chosen[0] if not chosen.is_empty() else [])}
		"study_keep_cards":
			payload = {"keep_indices": state.get("selected", [])}
		"study_hand_limit":
			payload = {"hand_indices": state.get("selected", [])}
		"black_rose_active_quest_limit", "black_rose_completed_quest_limit":
			payload = {"quest_indices": state.get("selected", [])}
	if payload.is_empty():
		return false
	var ok: bool = _game.submit_beta_input(player_index, payload)
	if ok:
		_stages.erase(player_index)
	return ok

func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value.keys():
			out[str(key)] = _json_safe(value[key])
		return out
	if value is Array:
		var out: Array = []
		for entry in value:
			out.append(_json_safe(entry))
		return out
	if value is Vector2i or value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector3i or value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Color:
		return value.to_html()
	if value is Object:
		return null
	return value
