"""Summarize isolated Godot method timing (inclusive/exclusive; nested, do not sum)."""
import json
import re
import sys
from pathlib import Path

if len(sys.argv) < 2:
    sys.exit('Usage: python summarize_submit_profile.py file1.log [file2.log ...]')

data = []
for name in sys.argv[1:]:
    path = Path(name)
    if not path.is_file():
        sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP missing log {path}')
    content = path.read_text(encoding='utf-8-sig', errors='replace')
    found = []
    sidecars = []
    for line in content.splitlines():
        file_marker = 'BRWR_SUBMIT_PROFILE_FILE '
        if file_marker in line:
            sidecar = Path(line.split(file_marker, 1)[1].strip().strip('"'))
            if not sidecar.is_file():
                sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP missing sidecar {sidecar} listed in {path}')
            sidecars.append(sidecar)
        inline_marker = 'BRWR_SUBMIT_PROFILE_JSON '
        if inline_marker in line:
            try:
                found.append(json.loads(line.split(inline_marker, 1)[1].strip()))
            except json.JSONDecodeError as exc:
                sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP broken inline JSON in {path}: {exc}')
    # Prefer sidecar format. Retain compatibility with the old inline format.
    if sidecars:
        if len(sidecars) != 1:
            sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP expected one sidecar marker in {path}, got {len(sidecars)}')
        try:
            profile = json.loads(sidecars[0].read_text(encoding='utf-8-sig'))
        except (json.JSONDecodeError, OSError) as exc:
            sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP unreadable sidecar {sidecars[0]}: {exc}')
        found = [profile]
    if len(found) != 1:
        messages = [line for line in content.splitlines() if any(k in line for k in (
            'SCRIPT ERROR', 'SUBMIT_PROFILE', 'Invalid call', 'ERROR:'))]
        sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP expected 1 profile in {path}, got {len(found)}\n'
                 + '\n'.join(messages[-12:]))
    if 'AI_EPISODE_COMPLETE' not in path.read_text(encoding='utf-8-sig',errors='replace'):
        sys.exit(f'SUBMIT_PROFILE_SUMMARY_STOP incomplete episode {path}')
    data.append(found[0])

num_decisions = sum(int(x['decisions']) for x in data)
total_step_s = sum(int(x['bridge_step_us']) for x in data)/1e6
stats = {}
for game in data:
    for label, val in game['functions'].items():
        item = stats.setdefault(label, {'calls':0, 'inclusive_us':0, 'exclusive_us':0})
        for k in item:
            item[k] += int(val[k])

print('========== BRWR SUBMIT/RESOLUTION PROFILE ==========')
print(f'Games: {len(data)} | decisions: {num_decisions} | bridge.step total: {total_step_s:.3f}s | {total_step_s*1000/max(1,num_decisions):.2f} ms/decision')
print('INCLUSIVE = time including wrapped child functions. EXCLUSIVE = excluding wrapped child functions.')
print('Do NOT sum inclusive timings of nested functions.')
print('--- Slowest functions by EXCLUSIVE time ---')
print(f'{"Function":43s} {"Calls":>8} {"Self_s":>9} {"Incl_s":>9} {"Self_ms/call":>13}')
for label,item in sorted(stats.items(), key=lambda kv: kv[1]['exclusive_us'],reverse=True)[:24]:
    print(f'{label[:43]:43s} {item["calls"]:8d} {item["exclusive_us"]/1e6:9.3f} {item["inclusive_us"]/1e6:9.3f} {item["exclusive_us"]/1000/max(1,item["calls"]):13.3f}')
print('--- Top-level checkpoints (INCLUSIVE, nested) ---')
for name in ('submit_beta_input','_dispatch_beta_input', 'process_resolution_stack',
             'refresh_all_player_boards', 'request_player_input','clear_player_input'):
    item=stats.get(name)
    if item:
        print(f'  {name:35s} calls={item["calls"]:6d} inclusive={item["inclusive_us"]/1e6:8.3f}s exclusive={item["exclusive_us"]/1e6:8.3f}s')
summary={'games':len(data),'decisions':num_decisions,'bridge_step_us':round(total_step_s*1e6),
         'stats':stats,'game_seeds':[int(x['seed']) for x in data]}
out=Path(sys.argv[1]).parent/'submit_profile_summary.json'
out.write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(f'SUBMIT_PROFILE_COMPLETE summary={out}')
print('====================================================')
