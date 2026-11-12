# Diagnostic only: full 384-feature parity, neural score on Python features,
# and old v4 categorical hash buckets. No game launch or training.
extends SceneTree
const V5Policy = preload("res://ai/ai_native_policy_v5.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var policy = V5Policy.new()
	if not policy.load_model("res://ai/model/native_policy_v5.json"):
		printerr("V5_SCORE_DIAG_STOP failed loading native policy")
		quit(1)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ai/model/v5_score_diagnostic_probe.json"))
	if not raw is Dictionary or not raw.get("cases", []) is Array:
		printerr("V5_SCORE_DIAG_STOP missing/invalid diagnostic probe")
		quit(1)
		return
	var cases: Array = raw["cases"]
	var failed := 0
	var worst_feature := 0.0
	var worst_score := 0.0
	for item in cases:
		var ref_features := PackedFloat32Array(item["expected_features"])
		var actual_features: PackedFloat32Array = policy.encode_action(item["observation"], item["decision"], item["option"], int(item["index"]), int(item["total_options"]))
		if ref_features.size() != 384 or actual_features.size() != 384:
			printerr("V5_SCORE_DIAG_SHAPE case=", item["case"], " reference=", ref_features.size(), " native=", actual_features.size())
			failed += 1
			continue
		var nbad := 0
		var local_worst := 0.0
		for k in range(384):
			var delta := absf(float(ref_features[k]) - float(actual_features[k]))
			local_worst = maxf(local_worst, delta)
			if delta > 0.00001:
				nbad += 1
				if nbad <= 12:
					var section := "BASE_V4" if k < 128 else "SEMANTIC_V5"
					print("V5_SCORE_DIAG_FEATURE case=", item["case"], " index=", k, " section=", section,
						" python=", ref_features[k], " godot=", actual_features[k], " delta=", delta)
		worst_feature = maxf(worst_feature, local_worst)
		var score_actual: float = policy.score(actual_features)
		var score_python_features: float = policy.score(ref_features)
		var expected: float = float(item["expected_score"])
		var delta_score := absf(score_actual - expected)
		var delta_model := absf(score_python_features - expected)
		worst_score = maxf(worst_score, delta_score)
		if nbad > 0 or delta_score > 0.0001:
			failed += 1
			print("V5_SCORE_DIAG_CASE case=", item["case"], " type=", str(item["decision"].get("type", "")),
				" feature_mismatches=", nbad, " max_feature_diff=", local_worst,
				" python_score=", expected, " native_score=", score_actual,
				" score_with_python_features=", score_python_features,
				" encoding_score_delta=", absf(score_actual - score_python_features),
				" native_math_delta=", delta_model)
			var bad_hashes := 0
			for token_item in item.get("v4_tokens", []):
				var token := str(token_item["token"])
				var expected_bucket := int(token_item["bucket"])
				var native_bucket := policy.bucket(token)
				if native_bucket != expected_bucket:
					bad_hashes += 1
					print("V5_SCORE_DIAG_HASH case=", item["case"], " token=", token,
						" python_bucket=", expected_bucket, " godot_bucket=", native_bucket)
			print("V5_SCORE_DIAG_HASH_SUMMARY case=", item["case"], " mismatches=", bad_hashes)
	print("V5_SCORE_DIAGNOSTIC_COMPLETE cases=", cases.size(), " mismatch_cases=", failed,
		" max_feature_diff=", worst_feature, " max_score_diff=", worst_score,
		" no_training=1")
	# Nonzero differences are the point of this diagnostic, not a Godot execution failure.
	quit(0)
