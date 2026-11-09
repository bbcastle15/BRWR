# Run: Godot --headless --path . --script res://ai/ai_native_policy_validation.gd
extends SceneTree
const Policy = preload("res://ai/ai_native_policy_v4.gd")

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func():
		printerr("VALIDATION_TIMEOUT: aborted after 20 seconds")
		quit(2)
	)
	call_deferred("_run")

func _run() -> void:
	var policy = Policy.new()
	if not policy.load_model("res://ai/model/native_policy_v4.json"):
		quit(1)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ai/model/native_policy_probe_v4.json"))
	if not raw is Dictionary:
		printerr("VALIDATION_FAIL: invalid probe file")
		quit(1)
		return
	var failure_count := 0
	for item in raw.get("hash_tests", []):
		# Test the fallback implementation, deliberately bypassing exported cache.
		var got: int = policy._blake2b8_bucket(str(item["token"]))
		if got != int(item["expected_bucket"]):
			printerr("HASH_MISMATCH token=", str(item["token"]).substr(0, 50), " expected=", item["expected_bucket"], " got=", got)
			failure_count += 1
	var case_count := 0
	var value_max_diff := 0.0
	var score_max_diff := 0.0
	for item in raw.get("cases", []):
		var obs: Dictionary = item["observation"]
		var decision: Dictionary = item["decision"]
		var total: int = int(item["total_options"])
		for sample in item["samples"]:
			case_count += 1
			# JSON.parse_string converts integer JSON values to float on Godot.
			# Restore original Python type for ai_select when it was an integer.
			# This changes ONLY the test sample, not the runtime policy.
			var runtime_option: Dictionary = sample["option"].duplicate(true)
			if sample.get("ai_select_was_int", false):
				var restored_payload: Dictionary = runtime_option.get("payload", {})
				if restored_payload.has("ai_select"):
					restored_payload["ai_select"] = int(restored_payload["ai_select"])
					runtime_option["payload"] = restored_payload
			var encoded: PackedFloat32Array = policy.encode_action(obs, decision, runtime_option, int(sample["index"]), total)
			if encoded.size() != 128:
				printerr("VALIDATION_FAIL: encode_action returned ", encoded.size(), " features (expected 128), case=", case_count)
				quit(1)
				return
			var expected_terms: Array = sample.get("expected_terms", [])
			var expected_buckets: Array = sample.get("expected_buckets", [])
			var got_terms: Array[String] = policy.diagnostic_terms(obs, decision, runtime_option)
			var term_errors := 0
			for ti in range(maxi(got_terms.size(), expected_terms.size())):
				var py_term := str(expected_terms[ti]) if ti < expected_terms.size() else "<missing>"
				var gd_term := str(got_terms[ti]) if ti < got_terms.size() else "<missing>"
				var py_bucket := int(expected_buckets[ti]) if ti < expected_buckets.size() else -1
				var gd_bucket := policy.bucket(gd_term) if ti < got_terms.size() else -1
				if py_term != gd_term or py_bucket != gd_bucket:
					printerr("TERM_MISMATCH case=", case_count, " term=", ti,
						" python=", JSON.stringify(py_term), " godot=", JSON.stringify(gd_term),
						" python_bucket=", py_bucket, " godot_bucket=", gd_bucket)
					term_errors += 1
					failure_count += 1
			if term_errors > 0:
				printerr("CASE_DATA case=", case_count, " request=", str(decision.get("type", "")),
					" payload=", JSON.stringify(sample["option"].get("payload", {})),
					" detail=", JSON.stringify(sample["option"].get("detail", {})))
			var wanted: Array = sample["expected_features"]
			for i in range(128):
				var diff := absf(encoded[i] - float(wanted[i]))
				value_max_diff = maxf(value_max_diff, diff)
				if diff > 0.00002:
					printerr("FEATURE_MISMATCH case=", case_count, " index=", i, " diff=", diff)
					failure_count += 1
			var actual: float = policy.score(encoded)
			var score_diff: float = absf(actual - float(sample["expected_score"]))
			score_max_diff = maxf(score_max_diff, score_diff)
			if score_diff > 0.0003:
				printerr("SCORE_MISMATCH case=", case_count, " diff=", score_diff)
				failure_count += 1
	print("NATIVE_POLICY_PARITY cases=", case_count, " max_feature_diff=", value_max_diff,
		" max_logit_diff=", score_max_diff, " mismatches=", failure_count)
	if case_count == 0:
		printerr("NO_DATASET_CASES: real feature/logit parity NOT verified")
		quit(2)
	else:
		quit(0 if failure_count == 0 else 1)
