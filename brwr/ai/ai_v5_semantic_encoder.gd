# Experimental BRWR v5 encoder parity probe ONLY. No v5 inference / training yet.
# Uses owner-visible observation and the unmodified v4 base 128 features.
extends "res://ai/ai_native_policy_v4.gd"

const V5_SEMANTIC_DIM := 256
const V5_FEATURE_DIM := 384
const V5_VOLATILE := ["instance", "instance_id", "object_id", "revision", "signature", "timestamp", "feedback_serial", "global_position", "screen_position", "position", "x", "y", "id_hash", "request_key"]
const V5_TEXT_IGNORE := ["label", "name", "spell_name", "personal_spell_name", "grimoire_name"]
const V5_INDICES := ["ready_hand_indices", "quick_hand_index", "keep_indices", "hand_index", "hand_indices", "draw_index", "return_to_hand_indices", "active_index", "quest_index", "quest_indices", "queue_index", "evocation_index"]
const V5_NUMERICS := ["health", "speed", "strength", "hand_limit", "power", "progress", "cube_slots", "count", "damage", "distance", "max_select", "min_select", "ai_count", "ready_count"]
var _v5_bucket_cache: Dictionary = {}

func _v5_text(value: String) -> String:
	var t := value.strip_edges().to_lower()
	if not t.contains(":"):
		return t
	var ix := t.find(":")
	var prefix := t.substr(0, ix)
	var suffix := t.substr(ix + 1)
	if (suffix.is_valid_int() and suffix.length() >= 8) or (prefix in ["hand", "action"] and suffix.is_valid_int()):
		return prefix + ":<runtime-id>"
	return t

func _v5_leaf_tokens(value: Variant, path: String, key: String, terms: Array[String], depth: int) -> void:
	if depth > 7 or key in V5_VOLATILE:
		return
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		for subkey in keys:
			if subkey is String:
				_v5_leaf_tokens(value[subkey], path + "." + subkey, subkey, terms, depth + 1)
	elif value is Array:
		terms.append(path + ".len=" + str(mini(64, value.size())))
		for ix in range(mini(64, value.size())):
			var item: Variant = value[ix]
			if item is Dictionary or item is Array:
				_v5_leaf_tokens(item, path + "[" + str(ix) + "]", key, terms, depth + 1)
			else:
				_v5_leaf_tokens(item, path + "[]", key, terms, depth + 1)
				_v5_leaf_tokens(item, path + "[" + str(ix) + "]", key, terms, depth + 1)
	elif value is bool:
		terms.append(path + "=" + ("true" if value else "false"))
	elif value is String:
		if key in V5_TEXT_IGNORE:
			return
		var t := _v5_text(value)
		if t != "" and t.length() <= 128:
			terms.append(path + "=" + t)
	elif value is int or value is float:
		if key in V5_INDICES:
			return
		if key in V5_NUMERICS and is_finite(float(value)) and absf(float(value)) < 100000.0:
			terms.append(path + "=" + str(roundi(float(value))))

func _v5_list_cards(obs: Dictionary, decision: Dictionary, key: String) -> Array:
	var pending: Dictionary = obs.get("pending_input", {}) if obs.get("pending_input", {}) is Dictionary else {}
	var players: Array = obs.get("players", [])
	var idx := int(decision.get("player_index", -1))
	var own: Dictionary = players[idx] if idx >= 0 and idx < players.size() and players[idx] is Dictionary else {}
	var result: Variant
	if key == "keep_indices" or key == "draw_index":
		result = pending.get("cards", [])
	elif key == "return_to_hand_indices" or key == "active_index":
		result = pending.get("active_spells", own.get("active_spells", []))
	elif key == "quest_index" or key == "quest_indices":
		result = pending.get("quests", own.get("active_quests", []))
	else:
		result = pending.get("hand", own.get("hand", []))
	return result if result is Array else []

func _v5_referenced_cards(obs: Dictionary, decision: Dictionary, option: Dictionary, terms: Array[String]) -> void:
	var payload: Dictionary = option.get("payload", {}) if option.get("payload", {}) is Dictionary else {}
	for key in V5_INDICES:
		if not payload.has(key):
			continue
		var raw: Variant = payload[key]
		var indices: Array = raw if raw is Array else [raw]
		var cards: Array = _v5_list_cards(obs, decision, key)
		for index in indices:
			if index is bool or not (index is float or index is int):
				continue
			if int(index) != index or int(index) < 0:
				continue
			var target := int(index)
			var matched: Variant = null
			var lookup := "hand_index"
			if key == "keep_indices" or key == "draw_index":
				lookup = "draw_index"
			elif key == "return_to_hand_indices" or key == "active_index":
				lookup = "active_index"
			elif key == "quest_index" or key == "quest_indices":
				lookup = "quest_index"
			for pos in range(cards.size()):
				var card: Variant = cards[pos]
				if not card is Dictionary:
					continue
				var raw_position: Variant = card.get(lookup, pos)
				if (raw_position is int or raw_position is float) and not raw_position is bool and raw_position == target:
					matched = card
					break
			if matched == null and target < cards.size():
				matched = cards[target]
			if matched is Dictionary:
				var identifier: Variant = matched.get("id", matched.get("spell_id", matched.get("school_id", "")))
				if identifier is String and identifier != "":
					terms.append("resolved." + key + "=" + _v5_text(identifier))

func v5_semantic_terms(obs: Dictionary, decision: Dictionary, option: Dictionary) -> Array[String]:
	var terms: Array[String] = []
	_v5_leaf_tokens(option.get("detail", {}), "detail", "detail", terms, 0)
	_v5_leaf_tokens(option.get("payload", {}), "payload", "payload", terms, 0)
	_v5_referenced_cards(obs, decision, option, terms)
	return terms

# Same RFC 7693 BLAKE2b-8 hashing used by the v4 policy, modulo 256.
func _v5_hash_bucket(text: String) -> int:
	if _v5_bucket_cache.has(text):
		return int(_v5_bucket_cache[text])
	var data: PackedByteArray = text.to_utf8_buffer()
	var h: Array = IV.duplicate()
	h[0] = h[0] ^ 0x01010008
	var pos := 0
	while true:
		var n := mini(128, data.size() - pos)
		var m: Array = []
		m.resize(16)
		for i in range(16):
			var word: int = 0
			for j in range(8):
				var k := i * 8 + j
				if k < n:
					word = word | (int(data[pos + k]) << (8 * j))
			m[i] = word
		var v: Array = h.duplicate()
		v.append_array(IV)
		v[12] = v[12] ^ (pos + n)
		var final_block := pos + n == data.size()
		if final_block:
			v[14] = ~v[14]
		for r in range(12):
			var s: Array = SIGMA[r % 10]
			_mix(v, 0,4,8,12,m[s[0]],m[s[1]])
			_mix(v, 1,5,9,13,m[s[2]],m[s[3]])
			_mix(v, 2,6,10,14,m[s[4]],m[s[5]])
			_mix(v, 3,7,11,15,m[s[6]],m[s[7]])
			_mix(v, 0,5,10,15,m[s[8]],m[s[9]])
			_mix(v, 1,6,11,12,m[s[10]],m[s[11]])
			_mix(v, 2,7,8,13,m[s[12]],m[s[13]])
			_mix(v, 3,4,9,14,m[s[14]],m[s[15]])
		for i in range(8):
			h[i] = h[i] ^ v[i] ^ v[i + 8]
		if final_block:
			break
		pos += n
	var bucket := 0
	for i in range(8):
		bucket = (bucket * 256 + ((h[0] >> (8 * i)) & 255)) % V5_SEMANTIC_DIM
	_v5_bucket_cache[text] = bucket
	return bucket

func v5_semantic_features(obs: Dictionary, decision: Dictionary, option: Dictionary) -> PackedFloat32Array:
	var terms := v5_semantic_terms(obs, decision, option)
	var result := PackedFloat32Array()
	result.resize(V5_SEMANTIC_DIM)
	var scale := 1.0 / sqrt(float(maxi(1, terms.size())))
	for term in terms:
		var ix := _v5_hash_bucket(term)
		result[ix] += scale
	return result

# BEGIN BRWR V5 NUMERIC SELECTION PARITY FIX
# Python renders integral numbers as "0", "3", ... when parsing JSON as int.
# Godot can parse the same numeric values as float and render "0.0", "3.0".
# This class alone overrides v4's categorical string formatter; v4 is untouched.
func _py_string(value: Variant) -> String:
	if value is bool:
		return "True" if value else "False"
	if value is float and is_finite(value) and absf(value) <= 9007199254740991.0:
		if value == float(int(value)):
			return str(int(value))
	return str(value)
# END BRWR V5 NUMERIC SELECTION PARITY FIX

func encode_action(obs: Dictionary, decision: Dictionary, option: Dictionary, choice_index: int, total_options: int) -> PackedFloat32Array:
	var result: PackedFloat32Array = super.encode_action(obs, decision, option, choice_index, total_options)
	result.append_array(v5_semantic_features(obs, decision, option))
	return result
