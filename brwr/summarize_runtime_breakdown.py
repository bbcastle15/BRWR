"""Summarize file-backed Godot runtime breakdown reports; no log encoding involved."""
from __future__ import annotations
import json
import sys
from pathlib import Path

FIELDS = [
    ('scene_load_us', 'Scene loading'),
    ('scene_instantiate_us', 'Scene instantiate'),
    ('root_add_child_us', 'Game _ready / add_child'),
    ('bootstrap_frames_us', '20 bootstrap frame waits'),
    ('start_game_flow_us', 'Start game flow'),
    ('bridge_decision_us', 'Legal actions: bridge.decision'),
    ('bridge_observation_us', 'Observations: bridge.observation'),
    ('native_choose_us', 'Native policy.choose'),
    ('bridge_step_us', 'Apply actions: bridge.step'),
    ('dataset_store_us', 'JSONL serialization + write'),
    ('dataset_flush_us', 'JSONL flush'),
    ('frame_wait_us', 'Game-loop await process_frame'),
]

def main():
    if len(sys.argv) <= 1:
        sys.exit('RUNTIME_BREAKDOWN_SUMMARY_STOP pass .runtime_profile.json files')
    profiles = []
    for x in sys.argv[1:]:
        p = Path(x)
        if not p.is_file():
            sys.exit(f'RUNTIME_BREAKDOWN_SUMMARY_STOP no report: {p}')
        j = json.loads(p.read_text(encoding='utf-8-sig'))
        for req in ('seed', 'decisions', 'total_us', *[f for f, _ in FIELDS]):
            if req not in j:
                sys.exit(f'RUNTIME_BREAKDOWN_SUMMARY_STOP {p} missing {req}')
        profiles.append(j)
    games, decisions = len(profiles), sum(int(x['decisions']) for x in profiles)
    total = sum(int(x['total_us']) for x in profiles)
    print('========== BRWR RUNTIME BREAKDOWN ==========', flush=True)
    print(f'Games: {games} | seeds: {[x["seed"] for x in profiles]} | decisions: {decisions}')
    print(f'Godot instrumented runtime: {total/1e6:.3f}s | {total/1e6/games:.3f}s/game')
    print(f'{"Component":40} {"Total_s":>9} {"ms/decision":>13} {"share":>7}')
    components = []
    for field, label in FIELDS:
        us = sum(int(x[field]) for x in profiles)
        components.append((label, us))
    for label, us in sorted(components, key=lambda x:x[1], reverse=True):
        print(f'{label:40} {us/1e6:9.3f} {us/1000/max(1,decisions):13.2f} {100*us/max(1,total):6.1f}%')
    tracked = sum(us for _, us in components)
    print(f'{"Other / uninstrumented":40} {(total-tracked)/1e6:9.3f} {(total-tracked)/1000/max(1,decisions):13.2f} {100*(total-tracked)/max(1,total):6.1f}%')
    # Non-overlapping spans above, except occasional edge sampling; residual can be +/- instrumentation jitter.
    frame = sum(int(x['frame_count']) for x in profiles)
    idle = sum(int(x['frame_idle_count']) for x in profiles)
    active = sum(int(x['frame_active_count']) for x in profiles)
    frame_us = sum(int(x['frame_wait_us']) for x in profiles)
    print(f'Frames: {frame} ({frame/max(1,decisions):.2f}/decision), avg wait {frame_us/1000/max(1,frame):.2f}ms; idle={idle}, awaiting input={active}')
    for p in profiles:
        print(f'  seed={p["seed"]} decisions={p["decisions"]} measured={int(p["total_us"])/1e6:.3f}s')
    print('RUNTIME_BREAKDOWN_COMPLETE')
    print('============================================')

if __name__ == '__main__':
    main()
