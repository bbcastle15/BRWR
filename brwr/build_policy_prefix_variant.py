#!/usr/bin/env python3
"""Create isolated, opt-in cached-state first-layer inference experiment.

Reads current source artifacts. Does not modify production game, existing policy,
existing cached worker, or any model files. Run from BRWR/brwr root.
"""
from pathlib import Path
import sys

root = Path.cwd()
source_policy = root / 'ai/ai_native_policy_v4.gd'
source_worker = root / 'ai/ai_policy_school_cached_match.gd'
game = root / 'ai/game_school_cached.gd'
for path in (source_policy, source_worker, game):
    if not path.is_file():
        sys.exit(f'PREFIX_POLICY_BUILD_STOP missing {path}')

policy = source_policy.read_text(encoding='utf-8-sig')
worker = source_worker.read_text(encoding='utf-8-sig')
cached_game = game.read_text(encoding='utf-8-sig')

# No unguarded fallback: the only intent here is to benchmark against the
# latest cache + 3 UI refresh guards, not an outdated worker version.
for function in ('refresh_all_player_boards', 'refresh_player_board', '_refresh_damage_boards'):
    i = cached_game.find('func ' + function + '(')
    if i < 0 or 'if not enable_beta_hud:\n\t\treturn' not in cached_game[i:i+340]:
        sys.exit('PREFIX_POLICY_BUILD_STOP missing AI HUD guard for ' + function)

sig = 'func choose(obs: Dictionary, decision: Dictionary) -> int:'
if policy.count(sig) != 1:
    sys.exit('PREFIX_POLICY_BUILD_STOP native choice signature missing/non-unique')
if not policy.strip().endswith('return options.size() - 1'):
    sys.exit('PREFIX_POLICY_BUILD_STOP current native choose differs; refusing unsafe patch')
if '_brwr_first_layer_prefix' in policy:
    sys.exit('PREFIX_POLICY_BUILD_STOP original policy already modified')

optimized = r'''# -------------------------------------------------------------------------
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
'''
# Preserve every byte of policy before the choice implementation.
new_policy = policy[:policy.index(sig)] + optimized

ref_path = 'res://ai/ai_native_policy_v4.gd'
fast_path = 'res://ai/ai_native_policy_prefix_v4.gd'
if worker.count(ref_path) != 1:
    sys.exit('PREFIX_POLICY_BUILD_STOP cached worker missing native policy reference')
if worker.count('school_cached_episode_') != 1:
    sys.exit('PREFIX_POLICY_BUILD_STOP cached worker episode filename anchor missing/nonunique')
new_worker = worker.replace(ref_path, fast_path, 1).replace('school_cached_episode_', 'school_prefix_episode_', 1)

out_policy = root / 'ai/ai_native_policy_prefix_v4.gd'
out_worker = root / 'ai/ai_policy_school_prefix_match.gd'
out_policy.write_text(new_policy, encoding='utf-8', newline='\n')
out_worker.write_text(new_worker, encoding='utf-8', newline='\n')
print('POLICY_PREFIX_BUILD_OK isolated=1 shared_features=17 original_policy_unchanged=1 rules_unchanged=1')
print('PREFIX_POLICY_FILE ' + str(out_policy))
print('PREFIX_WORKER_FILE ' + str(out_worker))
