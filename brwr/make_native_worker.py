"""Generate a separate Godot-only policy worker from *current* ai_policy_match.gd.
This script never edits original worker or engine files.
"""
from pathlib import Path

root = Path(__file__).resolve().parent
original = root / "ai/ai_policy_match.gd"
target = root / "ai/ai_policy_native_match.gd"
if not original.exists():
    raise SystemExit(f"Cannot find {original}")
s = original.read_text(encoding="utf-8")

old = 'const Bridge = preload("res://ai/ai_bridge.gd")'
assert s.count(old) == 1, "Unexpected worker preloads"
s = s.replace(old, old + '\nconst NativePolicy = preload("res://ai/ai_native_policy_v4.gd")', 1)

old = '\tvar bridge = Bridge.new(game)'
assert s.count(old) == 1, "Could not locate game bridge initialization"
s = s.replace(old,
    '\tvar policy = NativePolicy.new()\n'
    '\tif not policy.load_model("res://ai/model/native_policy_v4.json"):\n'
    '\t\toutput_file.close()\n'
    '\t\t_fail("Native model load failed")\n'
    '\t\treturn\n'
    '\tpolicy.set_seed(match_seed + 812341)\n'
    + old, 1)

old = 'var choice: int = await _choose_from_python(session_dir, decisions + 1, i, observation, decision)'
assert s.count(old) == 1, "Could not locate Python choice statement"
s = s.replace(old, 'var choice: int = policy.choose(observation, decision)', 1)
s = s.replace('Python policy failed to answer for decision', 'Native policy failed to choose for decision')
s = s.replace('policy_episode_', 'native_episode_')
s = s.replace('pytorch_self_play', 'native_gdscript_policy_v4')
# Avoid worker change for transition recording in initial controlled benchmark.
# Can disable transition logging in a subsequent optimization, once parity is validated.
target.write_text(s, encoding="utf-8")
print(f"NATIVE_WORKER_OK {target}")
