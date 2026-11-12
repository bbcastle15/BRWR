# Test only. Run with Godot --headless --path . --script res://ai/ai_v5_encoder_parity.gd
extends SceneTree
const Encoder = preload("res://ai/ai_v5_semantic_encoder.gd")

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ai/model/v5_encoder_probe.json"))
	if not raw is Dictionary or not raw.get("cases", []) is Array:
		printerr("V5_PARITY_STOP missing/invalid ai/model/v5_encoder_probe.json")
		quit(1)
		return
	var model = Encoder.new()
	var mismatches := 0
	var worst := 0.0
	var n := 0
	for item in raw.get("cases", []):
		var obs: Dictionary = item["observation"]
		var d: Dictionary = item["decision"]
		var option: Dictionary = item["option"]
		var expected: Array = item["expected_features"]
		var actual: PackedFloat32Array = model.v5_semantic_features(obs, d, option)
		if expected.size() != actual.size():
			mismatches += 1
			continue
		for i in range(expected.size()):
			var delta := absf(float(expected[i]) - float(actual[i]))
			worst = maxf(worst, delta)
			if delta > 0.00003:
				if mismatches < 10:
					printerr("V5_FEATURE_DIFF case=", n, " feature=", i, " got=", actual[i], " expected=", expected[i], " delta=", delta)
				mismatches += 1
		n += 1
	print("V5_SEMANTIC_PARITY cases=", n, " max_feature_diff=", worst, " mismatches=", mismatches)
	quit(0 if n > 0 and mismatches == 0 else 1)
