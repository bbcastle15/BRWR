# Godot vs Python full-probability parity for the Momentum-One hierarchical sampler.
# Does not execute an episode or modify a checkpoint.
extends SceneTree
const MomentumOnePolicy = preload("res://ai/ai_native_policy_v5_momentumone.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "res://ai/model/v5_momentumone_probe.json"
	if not FileAccess.file_exists(path):
		printerr("MOMENTUM_ONE_PARITY_FAIL missing probe")
		quit(1)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not doc is Dictionary or doc.get("cases", []) is not Array:
		printerr("MOMENTUM_ONE_PARITY_FAIL invalid probe")
		quit(1)
		return
	var model = MomentumOnePolicy.new()
	if str(doc.get("version", "")) != str(model.MOMENTUM_ONE_POLICY_VERSION):
		printerr("MOMENTUM_ONE_PARITY_FAIL version mismatch")
		quit(1)
		return
	var errors := 0
	var tested := 0
	var max_delta := 0.0
	for sample in doc["cases"]:
		var decision: Dictionary = {"type": sample["request_type"], "candidates": sample["candidates"]}
		var logits := PackedFloat32Array(sample["scores"])
		var expected: Array = sample["expected"]
		var got: PackedFloat64Array = model.momentumone_probabilities(decision, logits)
		if got.size() != expected.size():
			errors += 1
			continue
		for i in range(expected.size()):
			var delta: float = absf(got[i] - float(expected[i]))
			max_delta = maxf(max_delta, delta)
			if delta > 0.000005:
				errors += 1
		tested += 1
	print("MOMENTUM_ONE_PARITY cases=", tested, " max_abs_diff=", max_delta, " mismatches=", errors)
	quit(0 if errors == 0 and tested >= 4 else 1)
