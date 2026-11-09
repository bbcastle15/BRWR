"""Create an instrumented COPY of the current Godot AI worker.

Does not modify ai/ai_policy_match.gd, train.py, or training checkpoints.
Run from project root: python profile_worker_patch.py
"""
from pathlib import Path
import sys

root = Path.cwd()
src = root / 'ai' / 'ai_policy_match.gd'
dst = root / 'ai' / 'ai_policy_match_profile.gd'

if not (root / 'project.godot').is_file() or not src.is_file():
    raise SystemExit('Esegui dalla cartella brwr che contiene project.godot e ai/ai_policy_match.gd.')

text = src.read_text(encoding='utf-8-sig')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'Worker non compatibile: {label}: attesa 1 occorrenza, trovate {count}. Nessun file originale modificato.')
    text = text.replace(old, new, 1)


replace_once(
    'func _initialize() -> void:\n',
    '''# Isolated performance counters; timings use a monotonic clock.
var _profile_started_us: int = Time.get_ticks_usec()
var _p_decision_us: int = 0
var _p_observation_us: int = 0
var _p_step_us: int = 0
var _p_store_us: int = 0
var _p_request_write_us: int = 0
var _p_response_wait_us: int = 0
var _p_response_read_us: int = 0
var _p_poll_fs_us: int = 0
var _p_frame_us: int = 0
var _p_polls: int = 0
var _p_frames: int = 0


func _initialize() -> void:
''', 'profiling globals')

replace_once(
    '\t\t\t\tvar decision: Dictionary = bridge.decision(i)\n',
    '''\t\t\t\tvar _p_t0: int = Time.get_ticks_usec()
\t\t\t\tvar decision: Dictionary = bridge.decision(i)
\t\t\t\t_p_decision_us += Time.get_ticks_usec() - _p_t0
''', 'bridge.decision')
replace_once(
    '\t\t\t\tvar observation: Dictionary = bridge.observation(i)\n',
    '''\t\t\t\t_p_t0 = Time.get_ticks_usec()
\t\t\t\tvar observation: Dictionary = bridge.observation(i)
\t\t\t\t_p_observation_us += Time.get_ticks_usec() - _p_t0
''', 'bridge.observation')
replace_once(
    '\t\t\t\tif not bridge.step(i, choice, str(decision.get("signature", ""))):\n',
    '''\t\t\t\t_p_t0 = Time.get_ticks_usec()
\t\t\t\tvar _p_step_ok: bool = bridge.step(i, choice, str(decision.get("signature", "")))
\t\t\t\t_p_step_us += Time.get_ticks_usec() - _p_t0
\t\t\t\tif not _p_step_ok:
''', 'bridge.step')
replace_once(
    '\t\tawait process_frame\n\n\tif not game.game_has_ended:',
    '''\t\tvar _p_frame_start: int = Time.get_ticks_usec()
\t\tawait process_frame
\t\t_p_frame_us += Time.get_ticks_usec() - _p_frame_start
\t\t_p_frames += 1

\tif not game.game_has_ended:''', 'main loop process_frame')
replace_once(
    '''\toutput_file.close()
\tprint("AI_EPISODE_COMPLETE seed=",''',
    '''\toutput_file.close()
\tvar _p_total_us: int = Time.get_ticks_usec() - _profile_started_us
\tprint("AI_PROFILE_JSON " + JSON.stringify({
\t\t"total_ms": _p_total_us / 1000.0,
\t\t"bridge_decision_ms": _p_decision_us / 1000.0,
\t\t"bridge_observation_ms": _p_observation_us / 1000.0,
\t\t"bridge_step_ms": _p_step_us / 1000.0,
\t\t"dataset_store_ms": _p_store_us / 1000.0,
\t\t"request_write_ms": _p_request_write_us / 1000.0,
\t\t"response_wait_ms": _p_response_wait_us / 1000.0,
\t\t"response_read_ms": _p_response_read_us / 1000.0,
\t\t"response_poll_file_check_ms": _p_poll_fs_us / 1000.0,
\t\t"frame_and_engine_ms": _p_frame_us / 1000.0,
\t\t"frame_count": _p_frames,
\t\t"response_poll_count": _p_polls,
\t\t"decisions": decisions
\t}))
\tprint("AI_EPISODE_COMPLETE seed=",''', 'end-of-game profile')
replace_once(
    '''func _store(target: FileAccess, entry: Dictionary) -> void:
\ttarget.store_line(JSON.stringify(entry))''',
    '''func _store(target: FileAccess, entry: Dictionary) -> void:
\tvar _p_store_start: int = Time.get_ticks_usec()
\ttarget.store_line(JSON.stringify(entry))
\t_p_store_us += Time.get_ticks_usec() - _p_store_start''', 'dataset store')
replace_once(
    '''\tvar request_file: FileAccess = FileAccess.open(request_path, FileAccess.WRITE)''',
    '''\tvar _p_write_start: int = Time.get_ticks_usec()
\tvar request_file: FileAccess = FileAccess.open(request_path, FileAccess.WRITE)''', 'request write begin')
replace_once(
    '''\trequest_file.close()
\tvar deadline_ms: int = Time.get_ticks_msec() + RESPONSE_TIMEOUT_MS''',
    '''\trequest_file.close()
\t_p_request_write_us += Time.get_ticks_usec() - _p_write_start
\tvar _p_wait_start: int = Time.get_ticks_usec()
\tvar deadline_ms: int = Time.get_ticks_msec() + RESPONSE_TIMEOUT_MS''', 'request write end')
replace_once(
    '''\t\tif FileAccess.file_exists(response_path):
\t\t\tvar raw_response: String = FileAccess.get_file_as_string(response_path)
\t\t\tvar value: Variant = JSON.parse_string(raw_response)''',
    '''\t\tvar _p_poll_start: int = Time.get_ticks_usec()
\t\tvar _p_response_exists: bool = FileAccess.file_exists(response_path)
\t\t_p_poll_fs_us += Time.get_ticks_usec() - _p_poll_start
\t\t_p_polls += 1
\t\tif _p_response_exists:
\t\t\tvar _p_read_start: int = Time.get_ticks_usec()
\t\t\tvar raw_response: String = FileAccess.get_file_as_string(response_path)
\t\t\tvar value: Variant = JSON.parse_string(raw_response)
\t\t\t_p_response_read_us += Time.get_ticks_usec() - _p_read_start''', 'response poll/read')
replace_once(
    '''\t\t\t\tDirAccess.remove_absolute(response_path)
\t\t\t\treturn picked''',
    '''\t\t\t\tDirAccess.remove_absolute(response_path)
\t\t\t\t_p_response_wait_us += Time.get_ticks_usec() - _p_wait_start
\t\t\t\treturn picked''', 'response wait end')
replace_once(
    '''\tprinterr("AI_IPC_TIMEOUT: step ", step_id)''',
    '''\t_p_response_wait_us += Time.get_ticks_usec() - _p_wait_start
\tprinterr("AI_IPC_TIMEOUT: step ", step_id)''', 'response timeout')
replace_once(
    '"policy_episode_%d_%s.jsonl" % [match_seed, scenario]',
    '"profile_episode_%d_%s.jsonl" % [match_seed, scenario]', 'isolated dataset output')

# This is a new generated file, not an in-place modification of the active worker.
dst.write_text(text, encoding='utf-8', newline='\n')
print(f'Profiling worker creato: {dst}')
print('Originale ai/ai_policy_match.gd non modificato.')
