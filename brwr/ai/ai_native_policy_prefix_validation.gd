# Numerical and deterministic-choice parity: current native policy vs. prefix optimization.
# Run: Godot --headless --path . --script res://ai/ai_native_policy_prefix_validation.gd
extends SceneTree
const ReferencePolicy = preload("res://ai/ai_native_policy_v4.gd")
const FastPolicy = preload("res://ai/ai_native_policy_prefix_v4.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var reference = ReferencePolicy.new()
	var fast = FastPolicy.new()
	if not reference.load_model("res://ai/model/native_policy_v4.json") or not fast.load_model("res://ai/model/native_policy_v4.json"):
		printerr("POLICY_PREFIX_PARITY_FAIL: load_model")
		quit(1)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ai/model/native_policy_probe_v4.json"))
	if not raw is Dictionary:
		printerr("POLICY_PREFIX_PARITY_FAIL: missing probe JSON")
		quit(1)
		return
	var compared_scores := 0
	var compared_choices := 0
	var max_score_diff := 0.0
	var mismatch := 0
	for item in raw.get("cases", []):
		var obs: Dictionary = item["observation"]
		var decision: Dictionary = item["decision"].duplicate()
		var samples: Array = item["samples"]
		if samples.is_empty():
			continue
		var first_sample: Dictionary = samples[0]
		var first_features: PackedFloat32Array = fast.encode_action(obs, decision, first_sample["option"], int(first_sample["index"]), int(item["total_options"]))
		var prefix: PackedFloat64Array = fast._brwr_first_layer_prefix(first_features)
		for sample in samples:
			var features: PackedFloat32Array = fast.encode_action(obs, decision, sample["option"], int(sample["index"]), int(item["total_options"]))
			for ix in range(17):
				if features[ix] != first_features[ix]:
					printerr("POLICY_PREFIX_SHARED_FEATURE_MISMATCH i=", ix)
					mismatch += 1
			var a: float = reference.score(features)
			var b: float = fast._brwr_score_with_prefix(features, prefix)
			var diff: float = absf(a - b)
			max_score_diff = maxf(max_score_diff, diff)
			compared_scores += 1
			if diff > 0.000001:
				printerr("POLICY_PREFIX_SCORE_MISMATCH diff=", diff)
				mismatch += 1
		var candidates: Array = []
		for sample in samples:
			candidates.append(sample["option"])
		decision["candidates"] = candidates
		for seed_offset in range(12):
			reference.set_seed(20270491 + seed_offset)
			fast.set_seed(20270491 + seed_offset)
			var c1: int = reference.choose(obs, decision)
			var c2: int = fast.choose(obs, decision)
			compared_choices += 1
			if c1 != c2:
				printerr("POLICY_PREFIX_CHOICE_MISMATCH expected=", c1, " got=", c2)
				mismatch += 1
	print("POLICY_PREFIX_PARITY scores=", compared_scores, " max_score_diff=", max_score_diff, " sampled_choices=", compared_choices, " mismatches=", mismatch)
	if compared_scores < 1 or compared_choices < 1 or mismatch:
		quit(1)
	else:
		quit(0)
