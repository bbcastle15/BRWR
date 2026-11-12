# AI-only v5 policy: category-balanced sampling (action_activation_step ONLY).
# Scores/encoder and all model weights are inherited unchanged from v5.
# The Python loss must use v5_group_balanced.log_probabilities.
extends "res://ai/ai_native_policy_v5.gd"

const GROUP_POLICY_VERSION := "v5_action_family_balanced_logcount_v1"

func _brwr_family(option: Dictionary) -> String:
	var detail: Variant = option.get("detail", {})
	if not detail is Dictionary:
		return ""
	var descriptor: Variant = detail.get("descriptor", {})
	if not descriptor is Dictionary:
		return ""
	var family: Variant = descriptor.get("kind", "")
	if not family is String or family.is_empty():
		family = detail.get("kind", "")
	return str(family) if family is String else ""

# Exposed separately so a Godot check can compare full probability vectors
# against PyTorch, instead of checking only neural-network logits.
func balanced_probabilities(decision: Dictionary, scores: PackedFloat32Array) -> PackedFloat64Array:
	var options: Array = decision.get("candidates", [])
	var out := PackedFloat64Array()
	if scores.is_empty() or options.size() != scores.size():
		push_error("GROUP_POLICY_INVALID candidate/logit count")
		return out
	var families: Array[String] = []
	var counts := {}
	var is_action: bool = str(decision.get("type", "")) == "action_activation_step"
	for option in options:
		if not option is Dictionary:
			push_error("GROUP_POLICY_INVALID candidate type")
			return out
		var family := "__unchanged__"
		if is_action:
			family = _brwr_family(option)
			if family.is_empty():
				push_error("GROUP_POLICY_INVALID action family")
				return out
		families.append(family)
		counts[family] = int(counts.get(family, 0)) + 1
	var corrected := PackedFloat64Array()
	var max_score := -INF
	for i in range(scores.size()):
		var value: float = float(scores[i]) - log(float(counts[families[i]])) if is_action else float(scores[i])
		corrected.append(value)
		max_score = maxf(max_score, value)
	var total := 0.0
	for value in corrected:
		var weight := exp(value - max_score)
		out.append(weight)
		total += weight
	for i in range(out.size()):
		out[i] /= total
	return out

func choose(obs: Dictionary, decision: Dictionary) -> int:
	var options: Array = decision.get("candidates", [])
	if options.is_empty():
		return -1
	if options.size() == 1:
		return 0
	var first: PackedFloat32Array = encode_action(obs, decision, options[0], 0, options.size())
	var prefix: PackedFloat64Array = _v5_first_layer_prefix(first)
	var scores := PackedFloat32Array()
	for i in range(options.size()):
		var features: PackedFloat32Array = first if i == 0 else encode_action(obs, decision, options[i], i, options.size())
		scores.append(_v5_score_with_prefix(features, prefix))
	var probs := balanced_probabilities(decision, scores)
	if probs.size() != options.size():
		return -1
	var ticket: float = _rng.randf()
	for i in range(probs.size()):
		ticket -= probs[i]
		if ticket < 0.0:
			return i
	return options.size() - 1
