#!/usr/bin/env python3
"""Build an isolated, sequential, multi-episode Godot worker from current prefix worker.

IMPORTANT: rules and policy are not duplicated. This transforms the current,
AI-only, cache+UI-guarded, already-parity-tested single episode worker. It keeps
one PackedScene and one inference policy alive, but instantiates/frees a fresh
Game node for every episode and reseeds policy RNG for deterministic parity.
"""
from pathlib import Path
import re
import sys

ROOT = Path.cwd()
source = ROOT / 'ai' / 'ai_policy_school_prefix_match.gd'
out = ROOT / 'ai' / 'ai_policy_prefix_batch_match.gd'
cached = ROOT / 'ai' / 'game_school_cached.gd'
for p in (source, cached):
    if not p.is_file():
        sys.exit(f'PERSISTENT_BATCH_BUILD_STOP missing {p}')

s = source.read_text(encoding='utf-8-sig')
c = cached.read_text(encoding='utf-8-sig')
for name in ('refresh_all_player_boards', 'refresh_player_board', '_refresh_damage_boards'):
    start = c.find('func ' + name + '(')
    if start < 0 or 'if not enable_beta_hud:\n\t\treturn' not in c[start:start+340]:
        sys.exit(f'PERSISTENT_BATCH_BUILD_STOP missing HUD guard for {name}')

checks = {
    'SceneTree worker': 'extends SceneTree',
    'native prefix policy': 'const NativePolicy = preload("res://ai/ai_native_policy_prefix_v4.gd")',
    'starting entry point': 'call_deferred("_run")',
    'single episode': 'func _run() -> void:',
    'scene load': 'load("res://ai/game_school_cached.tscn")',
    'per-decision inference': 'policy.choose(observation, decision)',
    'unique output filename': 'school_prefix_episode_',
    'policy creation': '\tvar policy = NativePolicy.new()',
    'policy seeding': '\tpolicy.set_seed(match_seed + 812341)',
    'game tree insertion': '\troot.add_child(game)',
    'success marker': '\tprint("AI_EPISODE_FILE ", output_path)\n\tquit(0)',
    'standalone args': '\tvar args: PackedStringArray = OS.get_cmdline_user_args()',
}
for label, token in checks.items():
    if s.count(token) != 1:
        sys.exit(f'PERSISTENT_BATCH_BUILD_STOP {label}: wanted 1 anchor, got {s.count(token)}')

# Need a source worker that uses the tested prefix policy, no hidden fallbacks.
s = s.replace('call_deferred("_run")', 'call_deferred("_run_batch")', 1)
s = s.replace('func _run() -> void:', 'func _run_episode(episode_args: PackedStringArray) -> bool:', 1)
s = s.replace('\tvar args: PackedStringArray = OS.get_cmdline_user_args()',
              '\tvar args: PackedStringArray = episode_args', 1)
s = s.replace('var packed: PackedScene = load("res://ai/game_school_cached.tscn")',
              'var packed: PackedScene = _brwr_batch_scene', 1)

policy_block = (
    '\tvar policy = NativePolicy.new()\n'
    '\tif not policy.load_model("res://ai/model/native_policy_v4.json"):\n'
    '\t\toutput_file.close()\n'
    '\t\t_fail("Native model load failed")\n'
    '\t\treturn\n'
    '\tpolicy.set_seed(match_seed + 812341)'
)
if s.count(policy_block) != 1:
    sys.exit('PERSISTENT_BATCH_BUILD_STOP expected exact native policy creation block')
s = s.replace(policy_block,
    '\tvar policy = _brwr_batch_policy\n'
    '\tpolicy.set_seed(match_seed + 812341)', 1)
s = s.replace('school_prefix_episode_', 'batch_prefix_episode_', 1)

# Capture SceneTree child-count before adding Game to detect leaks between games.
s = s.replace('\troot.add_child(game)',
              '\tvar _brwr_children_before: int = root.get_child_count()\n'
              '\troot.add_child(game)', 1)

# End episode: deterministic scene cleanup; no global SceneTree.quit until batch end.
success = '\tprint("AI_EPISODE_FILE ", output_path)\n\tquit(0)'
replacement = '''\tprint("AI_EPISODE_FILE ", output_path)
	# Finish queued scene changes before starting the next independent match.
	game.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(game):
		_fail("Persistent worker: old Game instance survived queue_free")
		return false
	if root.get_child_count() != _brwr_children_before:
		_fail("Persistent worker: leaked root nodes; before=%d after=%d" % [_brwr_children_before, root.get_child_count()])
		return false
	return true'''
s = s.replace(success, replacement, 1)

# Every original `return` in the now-bool _run_episode was an error path.
start = s.index('func _run_episode(episode_args: PackedStringArray) -> bool:')
end = s.find('\nfunc _store(', start)
if end < 0:
    sys.exit('PERSISTENT_BATCH_BUILD_STOP worker _store function boundary missing')
episode = s[start:end]
old_bare = len(re.findall(r'(?m)^[\t ]*return[\t ]*$', episode))
if old_bare < 8:
    sys.exit(f'PERSISTENT_BATCH_BUILD_STOP fewer error-path returns than expected: {old_bare}')
episode = re.sub(r'(?m)^(\t+)return[\t ]*$', r'\1return false', episode)
s = s[:start] + episode + s[end:]

# Validate input manifest, load scene and model ONCE, then run each episode.
# The score policy's RNG is reseeded at _run_episode start.
new_functions = '''
var _brwr_batch_scene: PackedScene = null
var _brwr_batch_policy: Variant = null

func _run_batch() -> void:
	var cli_args: PackedStringArray = OS.get_cmdline_user_args()
	if cli_args.size() != 1:
		_fail("Usage: -- res://ai/persistent_batch_<id>.json")
		return
	var manifest_path: String = cli_args[0]
	if not FileAccess.file_exists(manifest_path):
		_fail("Persistent manifest missing: " + manifest_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		_fail("Invalid persistent manifest JSON")
		return
	var entries: Variant = parsed.get("episodes", [])
	if not entries is Array or entries.size() == 0 or entries.size() > 128:
		_fail("Persistent manifest must contain 1..128 episodes")
		return

	_brwr_batch_scene = load("res://ai/game_school_cached.tscn")
	if _brwr_batch_scene == null:
		_fail("Cannot load cached AI scene")
		return
	_brwr_batch_policy = NativePolicy.new()
	if not _brwr_batch_policy.load_model("res://ai/model/native_policy_v4.json"):
		_fail("Cannot load prefix policy model")
		return
	print("BRWR_PERSISTENT_BATCH_START episodes=", entries.size())
	for i in range(entries.size()):
		var episode: Variant = entries[i]
		if not episode is Dictionary:
			_fail("Malformed episode manifest entry " + str(i))
			return
		for required_key in ["seed", "bots", "avatar"]:
			if not episode.has(required_key):
				_fail("Missing " + required_key + " in manifest entry " + str(i))
				return
		# Godot JSON.parse_string can decode JSON numeric literals as float.
		# CLI arguments are strings and the episode parser requires valid integers.
		# Cast BOTH seed and bots: otherwise "20270491.0" or "4.0" is rejected.
		var episode_seed: int = int(episode["seed"])
		var episode_bots: int = int(episode["bots"])
		if float(episode_seed) != float(episode["seed"]) or float(episode_bots) != float(episode["bots"]):
			_fail("Persistent manifest requires integral seed and bots at index " + str(i))
			return
		var episode_args := PackedStringArray([
			str(episode_seed), str(episode_bots), str(episode["avatar"]),
			str(episode.get("difficulty", "apprentice")), str(episode.get("mode", "normal"))
		])
		var start_us: int = Time.get_ticks_usec()
		var completed: bool = await _run_episode(episode_args)
		if not completed:
			_fail("Persistent batch episode failed: " + str(episode_seed))
			return
		var duration_ms: float = float(Time.get_ticks_usec() - start_us) / 1000.0
		print("BRWR_PERSISTENT_EPISODE_OK index=", i + 1, " seed=", episode_seed, " wall_ms=", snappedf(duration_ms, 0.001))
	print("BRWR_PERSISTENT_BATCH_COMPLETE episodes=", entries.size())
	quit(0)
'''

insert_after = 'const RESPONSE_TIMEOUT_MS := 120000\n'
if s.count(insert_after) != 1:
    sys.exit('PERSISTENT_BATCH_BUILD_STOP constants anchor missing')
s = s.replace(insert_after, insert_after + new_functions, 1)

# Ensure no bogus references/creation remain and script still has required helpers.
for forbidden in ('call_deferred("_run")', '\tvar policy = NativePolicy.new()', 'school_prefix_episode_'):
    if forbidden in s:
        sys.exit(f'PERSISTENT_BATCH_BUILD_STOP incomplete rewrite {forbidden}')
if 'return false false' in s or 'return true false' in s:
    sys.exit('PERSISTENT_BATCH_BUILD_STOP malformed return conversion')
if s.count('BRWR_PERSISTENT_BATCH_COMPLETE') != 1:
    sys.exit('PERSISTENT_BATCH_BUILD_STOP missing marker')

out.write_text(s, encoding='utf-8', newline='\n')
print('PERSISTENT_BATCH_BUILD_OK generated=ai/ai_policy_prefix_batch_match.gd original_worker_unchanged=1')
print('PERSISTENT_BATCH_ISOLATION scene_fresh_per_episode=1 policy_shared=1 rng_reseeded=1 queued_game_freed=1 root_leak_guard=1')
