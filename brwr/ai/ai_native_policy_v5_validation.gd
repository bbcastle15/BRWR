# Compare actual 384-feature v5 native inference against PyTorch scores.
# Run via: Godot --headless --path . --script res://ai/ai_native_policy_v5_validation.gd
extends SceneTree
const V5Policy = preload("res://ai/ai_native_policy_v5.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = V5Policy.new()
	if not model.load_model("res://ai/model/native_policy_v5.json"):
		printerr("V5_POLICY_PARITY_FAIL model load failed")
		quit(1)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ai/model/v5_policy_probe.json"))
	if not doc is Dictionary or doc.get("cases", []) is not Array:
		printerr("V5_POLICY_PARITY_FAIL missing/invalid model probe")
		quit(1)
		return
	var errors := 0
	var tested := 0
	var maximum := 0.0
	for item in doc.get("cases", []):
		var features: PackedFloat32Array = model.encode_action(item["observation"], item["decision"], item["option"], int(item["index"]), int(item["total_options"]))
		if features.size() != 384:
			errors += 1
			continue
		var actual := model.score(features)
		var expected := float(item["expected_score"])
		var delta := absf(actual - expected)
		maximum = maxf(maximum, delta)
		if delta > 0.0001:
			if errors < 8:
				printerr("V5_POLICY_SCORE_DIFF sample=", tested, " expected=", expected, " got=", actual, " delta=", delta)
			errors += 1
		tested += 1
	print("V5_POLICY_PARITY cases=", tested, " max_abs_diff=", maximum, " mismatches=", errors)
	quit(0 if tested >= 12 and errors == 0 else 1)
