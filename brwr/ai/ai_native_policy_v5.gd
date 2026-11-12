# BRWR v5 - isolated semantic native policy, compatible with 384-feature PyTorch model.
# The owner-visible semantic encoder is inherited from the validated phase-1 code.
# Never load v4 model JSON here, even if the extra 256 inputs currently weigh zero.
extends "res://ai/ai_v5_semantic_encoder.gd"

const V5_FORMAT := "BRWR_NATIVE_V5_1"

func load_model(path: String) -> bool:
	_loaded = false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("V5 policy cannot open model: " + path)
		return false
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not raw is Dictionary or str(raw.get("format", "")) != V5_FORMAT or int(raw.get("feature_dim", -1)) != V5_FEATURE_DIM or str(raw.get("encoder_version", "")) != "brwr-v5-semantic-1":
		push_error("V5 policy model schema, encoder or dimensions invalid")
		return false
	var sizes: Array = [[96, V5_FEATURE_DIM], [48, 96], [1, 48]]
	var new_weights: Array = []
	var new_biases: Array = []
	for layer in range(3):
		var ws: Variant = raw.get("w%d" % layer, [])
		var bs: Variant = raw.get("b%d" % layer, [])
		if not ws is Array or not bs is Array or ws.size() != sizes[layer][0] * sizes[layer][1] or bs.size() != sizes[layer][0]:
			push_error("V5 policy bad layer " + str(layer))
			return false
		new_weights.append(PackedFloat32Array(ws))
		new_biases.append(PackedFloat32Array(bs))
	_weights = new_weights
	_biases = new_biases
	_bucket_cache = raw.get("token_buckets", {}).duplicate()
	_v5_bucket_cache.clear()
	_loaded = true
	return true

# The first 17 coordinates depend only on the observation/player. Preserve the
# original dot-product accumulation order (float64 prefix, no early float32 cast).
func _v5_first_layer_prefix(first: PackedFloat32Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(96)
	var w0: PackedFloat32Array = _weights[0]
	var b0: PackedFloat32Array = _biases[0]
	for o in range(96):
		var total := float(b0[o])
		var base := o * V5_FEATURE_DIM
		for i in range(17):
			if first[i] != 0.0:
				total += float(w0[base + i]) * float(first[i])
		out[o] = total
	return out

func _v5_score_with_prefix(features: PackedFloat32Array, prefix: PackedFloat64Array) -> float:
	if not _loaded or features.size() != V5_FEATURE_DIM:
		push_error("V5 policy not loaded or bad feature vector")
		return 0.0
	var nonzero := PackedInt32Array()
	for i in range(17, V5_FEATURE_DIM):
		if features[i] != 0.0:
			nonzero.append(i)
	var h0 := PackedFloat32Array()
	h0.resize(96)
	var w0: PackedFloat32Array = _weights[0]
	for o in range(96):
		var total := prefix[o]
		var base := o * V5_FEATURE_DIM
		for ix in nonzero:
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

func score(features: PackedFloat32Array) -> float:
	if features.size() != V5_FEATURE_DIM:
		push_error("V5 score feature dimension invalid")
		return 0.0
	return _v5_score_with_prefix(features, _v5_first_layer_prefix(features))

func choose(obs: Dictionary, decision: Dictionary) -> int:
	var options: Array = decision.get("candidates", [])
	if options.is_empty():
		return -1
	if options.size() == 1:
		return 0
	var first: PackedFloat32Array = encode_action(obs, decision, options[0], 0, options.size())
	var prefix: PackedFloat64Array = _v5_first_layer_prefix(first)
	var logits := PackedFloat32Array()
	for i in range(options.size()):
		var features: PackedFloat32Array = first if i == 0 else encode_action(obs, decision, options[i], i, options.size())
		logits.append(_v5_score_with_prefix(features, prefix))
	var maximum := -INF
	for x in logits:
		maximum = maxf(maximum, x)
	var probabilities := PackedFloat32Array()
	var sum_prob := 0.0
	for x in logits:
		var e := exp(x - maximum)
		probabilities.append(e)
		sum_prob += e
	var target := _rng.randf() * sum_prob
	for i in range(probabilities.size()):
		target -= probabilities[i]
		if target < 0.0:
			return i
	return options.size() - 1
