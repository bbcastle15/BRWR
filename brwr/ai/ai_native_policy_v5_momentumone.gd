# AI-only V5: one virtual Momentum action, regardless of movement/discard variants.
# Cast candidates remain independent first-stage choices. Explore/Fight/etc.
# remain single-family choices so thousands of paths do not dominate sampling.
# The trainer MUST use v5_momentum_one.log_probabilities() for identical loss.
extends "res://ai/ai_native_policy_v5.gd"

const MOMENTUM_ONE_POLICY_VERSION := "v5_momentum_one_cast_individual_v1"

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

func _stable_softmax(values: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if values.is_empty():
		return result
	var max_value := -INF
	for value in values:
		max_value = maxf(max_value, value)
	var total := 0.0
	for value in values:
		var weight: float = exp(value - max_value)
		result.append(weight)
		total += weight
	if total <= 0.0 or not is_finite(total):
		push_error("MOMENTUM_ONE_INVALID softmax normalization")
		return PackedFloat64Array()
	for i in range(result.size()):
		result[i] /= total
	return result

# Public to test complete sampling probabilities against the Python loss.
func momentumone_probabilities(decision: Dictionary, scores: PackedFloat32Array) -> PackedFloat64Array:
	var options: Array = decision.get("candidates", [])
	var empty := PackedFloat64Array()
	if scores.is_empty() or options.size() != scores.size():
		push_error("MOMENTUM_ONE_INVALID candidate/logit count")
		return empty
	var raw := PackedFloat64Array()
	for score in scores:
		if not is_finite(float(score)):
			push_error("MOMENTUM_ONE_INVALID nonfinite logit")
			return empty
		raw.append(float(score))
	if str(decision.get("type", "")) != "action_activation_step":
		return _stable_softmax(raw)

	# First level: each Cast remains a slot; all Momentum candidates share
	# one slot; Explore/Fight/Quest/etc. also share one slot per family.
	var slots: Array = []
	var family_indices := {}
	for i in range(options.size()):
		var option: Variant = options[i]
		if not option is Dictionary:
			push_error("MOMENTUM_ONE_INVALID candidate type")
			return empty
		var family: String = _brwr_family(option)
		if family.is_empty():
			push_error("MOMENTUM_ONE_INVALID missing action family")
			return empty
		if family == "cast":
			slots.append({"individual_index": i})
		else:
			if not family_indices.has(family):
				family_indices[family] = []
				slots.append({"family": family})
			family_indices[family].append(i)

	var slot_logits := PackedFloat64Array()
	for slot in slots:
		if slot.has("individual_index"):
			slot_logits.append(raw[int(slot["individual_index"])])
		else:
			var indices: Array = family_indices[slot["family"]]
			var summed := 0.0
			for index in indices:
				summed += raw[int(index)]
			slot_logits.append(summed / float(indices.size()))
	var first_stage := _stable_softmax(slot_logits)
	if first_stage.size() != slots.size():
		return empty

	var result := PackedFloat64Array()
	result.resize(options.size())
	for slot_index in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		var primary: float = first_stage[slot_index]
		if slot.has("individual_index"):
			result[int(slot["individual_index"])] = primary
		else:
			var indices: Array = family_indices[slot["family"]]
			var local_scores := PackedFloat64Array()
			for index in indices:
				local_scores.append(raw[int(index)])
			var conditional: PackedFloat64Array = _stable_softmax(local_scores)
			if conditional.size() != indices.size():
				return empty
			for i in range(indices.size()):
				result[int(indices[i])] = primary * conditional[i]
	return result

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
	var probs: PackedFloat64Array = momentumone_probabilities(decision, scores)
	if probs.size() != options.size():
		return -1
	var ticket: float = _rng.randf()
	for i in range(probs.size()):
		ticket -= probs[i]
		if ticket < 0.0:
			return i
	return options.size() - 1
