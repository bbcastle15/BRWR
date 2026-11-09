# Pure-GDScript inference of ai/python/train.py's ActionPolicy + encode_action.
# Never accesses hidden opponent data: consumes Bridge.observation/decision only.
# Validate using ai_native_policy_validation.gd before benchmarking.
extends RefCounted

const FEATURE_DIM := 128
const NUMERIC := 32
const BUCKETS := 96
const IV := [7640891576956012808, -4942790177534073029, 4354685564936845355, -6534734903238641935,
	5840696475078001361, -7276294671716946913, 2270897969802886507, 6620516959819538809]
const SIGMA := [
	[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],
	[14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3],
	[11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4],
	[7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8],
	[9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13],
	[2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9],
	[12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11],
	[13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10],
	[6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5],
	[10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0]
]

var _weights: Array = []  # three PackedFloat32Array tensors, row-major
var _biases: Array = []
var _bucket_cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _loaded := false

func load_model(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Native policy cannot open model: " + path)
		return false
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not raw is Dictionary or int(raw.get("feature_dim", -1)) != FEATURE_DIM:
		push_error("Native policy bad model JSON or feature dimension")
		return false
	var sizes := [[96, 128], [48, 96], [1, 48]]
	_weights.clear()
	_biases.clear()
	for layer in range(3):
		var ws: Array = raw.get("w%d" % layer, [])
		var bs: Array = raw.get("b%d" % layer, [])
		if ws.size() != sizes[layer][0] * sizes[layer][1] or bs.size() != sizes[layer][0]:
			push_error("Native policy wrong tensor size on layer %d" % layer)
			return false
		_weights.append(PackedFloat32Array(ws))
		_biases.append(PackedFloat32Array(bs))
	var cache: Dictionary = raw.get("token_buckets", {})
	_bucket_cache = cache.duplicate()
	_loaded = true
	return true

func set_seed(value: int) -> void:
	_rng.seed = value

func is_loaded() -> bool:
	return _loaded

# Hash matches hashlib.blake2b(data, digest_size=8) with big-endian digest modulo 96.
# Cache makes frequent hashes O(1); fallback is complete RFC 7693 BLAKE2b.
func bucket(text: String) -> int:
	if _bucket_cache.has(text):
		return int(_bucket_cache[text])
	var result: int = _blake2b8_bucket(text)
	_bucket_cache[text] = result
	return result

func _rotr64(x: int, n: int) -> int:
	return ((x >> n) & ((1 << (64 - n)) - 1)) | (x << (64 - n))

func _mix(v: Array, a: int, b: int, c: int, d: int, x: int, y: int) -> void:
	v[a] = (v[a] + v[b]) + x
	v[d] = _rotr64(v[d] ^ v[a], 32)
	v[c] = v[c] + v[d]
	v[b] = _rotr64(v[b] ^ v[c], 24)
	v[a] = (v[a] + v[b]) + y
	v[d] = _rotr64(v[d] ^ v[a], 16)
	v[c] = v[c] + v[d]
	v[b] = _rotr64(v[b] ^ v[c], 63)

func _blake2b8_bucket(text: String) -> int:
	var data: PackedByteArray = text.to_utf8_buffer()
	var h: Array = IV.duplicate()
	h[0] = h[0] ^ 0x01010008  # digest_size=8, unkeyed, fanout=1, depth=1
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
	# Python's int.from_bytes(digest, "big") uses the LITTLE-ENDIAN bytes of h[0]
	# in BIG-ENDIAN interpretation. Compute modularly without unsigned int overflow.
	var result := 0
	for i in range(8):
		result = (result * 256 + ((h[0] >> (8 * i)) & 255)) % BUCKETS
	return result

func _num(value: Variant, fallback: float = 0.0) -> float:
	if value == null:
		return fallback
	if value is bool:
		return 1.0 if value else 0.0
	if value is int or value is float:
		return float(value)
	if value is String and str(value).is_valid_float():
		return float(value)
	return fallback

func _py_string(value: Variant) -> String:
	if value is bool:
		return "True" if value else "False"
	return str(value)

# Python-compatible truthiness for values decoded from JSON.
# In particular, bool({}) is False in Python but is not a valid GDScript cast.
func _py_truth(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return value != 0.0
	if value is String:
		return not value.is_empty()
	if value is Dictionary:
		return not value.is_empty()
	if value is Array:
		return not value.is_empty()
	return true

func encode_action(obs: Dictionary, decision: Dictionary, option: Dictionary, choice_index: int, total_options: int) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(FEATURE_DIM)
	var player_index := int(decision.get("player_index", -1))
	var players: Array = obs.get("players", [])
	var own: Dictionary = players[player_index] if player_index >= 0 and player_index < players.size() else {}
	var mage: Dictionary = own.get("mage", {}) if own.get("mage", {}) is Dictionary else {}
	var avatar: Variant = obs.get("avatar", {})
	var payload: Dictionary = option.get("payload", {})
	var detail: Dictionary = option.get("detail", {})
	var action: Dictionary = detail.get("action", {}) if detail.get("action", {}) is Dictionary else {}
	var side: Dictionary = detail.get("side_features", {}) if detail.get("side_features", {}) is Dictionary else {}
	var stage := str(decision.get("substep", ""))
	v[0] = 1.0
	v[1] = minf(3.0, _num(obs.get("round")) / 12.0)
	v[2] = minf(1.0, float(players.size()) / 6.0)
	v[3] = maxf(0.0, float(player_index) / 6.0)
	v[4] = 1.0 if _py_truth(avatar) else 0.0
	v[5] = _num(own.get("power")) / 40.0
	v[6] = _num(own.get("hand_count", own.get("hand", []).size())) / 12.0
	v[7] = _num(own.get("available_cubes")) / 30.0
	v[8] = _num(mage.get("health")) / 12.0
	v[9] = _num(mage.get("speed")) / 5.0
	v[10] = _num(mage.get("strength")) / 5.0
	v[11] = 1.0 if _py_truth(mage.get("in_cell", false)) else 0.0
	var other_sum := 0.0
	var other_max := 0.0
	for i in range(players.size()):
		if i != player_index:
			var op: Dictionary = players[i]
			other_sum += _num(op.get("power"))
			other_max = maxf(other_max, _num(op.get("power")))
	v[12] = (other_sum / float(maxi(1, players.size() - 1))) / 40.0
	v[13] = other_max / 40.0
	v[14] = _num(obs.get("moon")) / 3.0
	v[15] = _num(obs.get("black_rose_power")) / 40.0
	v[16] = _num(own.get("ready_spell_count")) / 3.0
	v[17] = float(choice_index) / float(maxi(1, total_options - 1))
	v[18] = log(1.0 + float(total_options)) / 8.0
	v[19] = 1.0 if _py_truth(payload.get("ai_dark", payload.get("quick_dark_side", false))) else 0.0
	v[20] = _num(payload.get("ai_count")) / 3.0
	v[21] = 1.0 if int(_num(payload.get("ai_hand_index", -1), -1.0)) >= 0 else 0.0
	v[22] = 1.0 if payload.has("ai_finish") else 0.0
	v[23] = 1.0 if _py_truth(detail.get("instability", false)) else 0.0
	v[24] = 1.0 if _py_truth(detail.get("light", false)) else 0.0
	v[25] = 1.0 if _py_truth(detail.get("dark", false)) else 0.0
	v[26] = 1.0 if str(detail.get("side", "")).to_lower() == "dark" else 0.0
	v[27] = 1.0 if str(detail.get("side", "")).to_lower() == "light" else 0.0
	v[28] = _num(own.get("active_quest_count")) / 4.0
	v[29] = _num(own.get("completed_quest_count")) / 4.0
	v[30] = minf(1.0, float(obs.get("active_schools", []).size()) / 6.0)
	v[31] = 1.0 if stage == "quick_card" else 0.0
	var terms: Array[String] = [
		"req:" + str(decision.get("type", "")),
		"stage:" + stage,
		"ownschool:" + str(own.get("school_id", "")),
		"actionkind:" + str(detail.get("kind", "")),
		"actiontype:" + str(action.get("type", ""))
	]
	for key in ["spell_id", "school_id", "id", "side", "evocation"]:
		var val: Variant = detail.get(key, "")
		if val is String and val != "":
			terms.append(key + ":" + val)
	for key in ["mage_id", "school_id", "grimoire_id"]:
		var val: Variant = payload.get(key, "")
		if val is String and val != "":
			terms.append("choose_" + key + ":" + val)
	for key in ["type", "target", "range"]:
		if str(side.get(key, "")) != "":
			terms.append("side_" + key + ":" + str(side[key]))
	for effect_type in side.get("effect_types", []):
		terms.append("effect:" + str(effect_type))
	if payload.has("ai_select"):
		terms.append("selection:" + _py_string(payload["ai_select"]))
	if payload.has("token"):
		terms.append("token_kind:" + str(payload["token"]).split(":")[0])
	for item in payload.get("school_ids", []):
		terms.append("draw_school:" + str(item))
	var scale := 1.0 / sqrt(float(maxi(1, terms.size())))
	for token in terms:
		var ix := NUMERIC + bucket(token)
		v[ix] += scale
	return v

# Diagnostic companion to encode_action. Returns exact categorical terms before hashing.
func diagnostic_terms(obs: Dictionary, decision: Dictionary, option: Dictionary) -> Array[String]:
	var player_index := int(decision.get("player_index", -1))
	var players: Array = obs.get("players", [])
	var own: Dictionary = players[player_index] if player_index >= 0 and player_index < players.size() else {}
	var payload: Dictionary = option.get("payload", {})
	var detail: Dictionary = option.get("detail", {})
	var action: Dictionary = detail.get("action", {}) if detail.get("action", {}) is Dictionary else {}
	var side: Dictionary = detail.get("side_features", {}) if detail.get("side_features", {}) is Dictionary else {}
	var stage := str(decision.get("substep", ""))
	var terms: Array[String] = [
		"req:" + str(decision.get("type", "")),
		"stage:" + stage,
		"ownschool:" + str(own.get("school_id", "")),
		"actionkind:" + str(detail.get("kind", "")),
		"actiontype:" + str(action.get("type", ""))
	]
	for key in ["spell_id", "school_id", "id", "side", "evocation"]:
		var val: Variant = detail.get(key, "")
		if val is String and val != "":
			terms.append(key + ":" + val)
	for key in ["mage_id", "school_id", "grimoire_id"]:
		var val: Variant = payload.get(key, "")
		if val is String and val != "":
			terms.append("choose_" + key + ":" + val)
	for key in ["type", "target", "range"]:
		if str(side.get(key, "")) != "":
			terms.append("side_" + key + ":" + str(side[key]))
	for effect_type in side.get("effect_types", []):
		terms.append("effect:" + str(effect_type))
	if payload.has("ai_select"):
		terms.append("selection:" + _py_string(payload["ai_select"]))
	if payload.has("token"):
		terms.append("token_kind:" + str(payload["token"]).split(":")[0])
	for item in payload.get("school_ids", []):
		terms.append("draw_school:" + str(item))
	return terms

func score(features: PackedFloat32Array) -> float:
	if not _loaded:
		push_error("Native policy not loaded")
		return 0.0
	# Sparse first layer; most of 128 encoded features are zero.
	var nonzero_indices := PackedInt32Array()
	for i in range(FEATURE_DIM):
		if features[i] != 0.0:
			nonzero_indices.append(i)
	var h0 := PackedFloat32Array()
	h0.resize(96)
	var w0: PackedFloat32Array = _weights[0]
	var b0: PackedFloat32Array = _biases[0]
	for o in range(96):
		var total := float(b0[o])
		var base := o * FEATURE_DIM
		for ix in nonzero_indices:
			total += float(w0[base + ix]) * float(features[ix])
		h0[o] = tanh(total)
	var h1 := PackedFloat32Array()
	h1.resize(48)
	var w1: PackedFloat32Array = _weights[1]
	var b1: PackedFloat32Array = _biases[1]
	for o in range(48):
		var total := float(b1[o])
		var base := o * 96
		for i in range(96):
			total += float(w1[base + i]) * float(h0[i])
		h1[o] = tanh(total)
	var total := float(_biases[2][0])
	var w2: PackedFloat32Array = _weights[2]
	for i in range(48):
		total += float(w2[i]) * float(h1[i])
	return total

# -------------------------------------------------------------------------
# AI-only controlled experiment: cache the first 17 features of the FIRST
# LAYER across candidate actions from a single decision.
# These 17 features depend only on the observation and player, not on choice.
# The double-precision prefix preserves the original accumulation order;
# using PackedFloat32Array here would introduce an intermediate rounding.
# -------------------------------------------------------------------------
func _brwr_first_layer_prefix(first_features: PackedFloat32Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(96)
	var w0: PackedFloat32Array = _weights[0]
	var b0: PackedFloat32Array = _biases[0]
	for o in range(96):
		var total := float(b0[o])
		var base := o * FEATURE_DIM
		for ix in range(17):
			if first_features[ix] != 0.0:
				total += float(w0[base + ix]) * float(first_features[ix])
		result[o] = total
	return result

func _brwr_score_with_prefix(features: PackedFloat32Array, prefix: PackedFloat64Array) -> float:
	# Same operations as score(features), in the same per-neuron feature order.
	var nonzero_indices := PackedInt32Array()
	for i in range(17, FEATURE_DIM):
		if features[i] != 0.0:
			nonzero_indices.append(i)
	var h0 := PackedFloat32Array()
	h0.resize(96)
	var w0: PackedFloat32Array = _weights[0]
	for o in range(96):
		var total := prefix[o]
		var base := o * FEATURE_DIM
		for ix in nonzero_indices:
			total += float(w0[base + ix]) * float(features[ix])
		h0[o] = tanh(total)
	var h1 := PackedFloat32Array()
	h1.resize(48)
	var w1: PackedFloat32Array = _weights[1]
	var b1: PackedFloat32Array = _biases[1]
	for o in range(48):
		var total := float(b1[o])
		var base := o * 96
		for i in range(96):
			total += float(w1[base + i]) * float(h0[i])
		h1[o] = tanh(total)
	var total := float(_biases[2][0])
	var w2: PackedFloat32Array = _weights[2]
	for i in range(48):
		total += float(w2[i]) * float(h1[i])
	return total

func choose(obs: Dictionary, decision: Dictionary) -> int:
	var options: Array = decision.get("candidates", [])
	if options.is_empty():
		return -1
	if options.size() == 1:
		return 0
	var first_features: PackedFloat32Array = encode_action(obs, decision, options[0], 0, options.size())
	var prefix: PackedFloat64Array = _brwr_first_layer_prefix(first_features)
	var logits := PackedFloat32Array()
	for i in range(options.size()):
		var features: PackedFloat32Array = first_features if i == 0 else encode_action(obs, decision, options[i], i, options.size())
		logits.append(_brwr_score_with_prefix(features, prefix))
	var maximum := -INF
	for x in logits:
		maximum = maxf(maximum, x)
	var prob := PackedFloat32Array()
	var sum_prob := 0.0
	for x in logits:
		var e := exp(x - maximum)
		prob.append(e)
		sum_prob += e
	var target := _rng.randf() * sum_prob
	for i in range(prob.size()):
		target -= prob[i]
		if target < 0.0:
			return i
	return options.size() - 1
