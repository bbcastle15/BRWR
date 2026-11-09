#!/usr/bin/env python3
"""Diagnose already-existing persistent A/B episode files WITHOUT running Godot."""
from pathlib import Path
import sys
from check_persistent_episode_parity import compare_files

root = Path.cwd()
datasets = root / 'ai' / 'datasets'
if not datasets.is_dir():
    sys.exit(f'DIAG_STOP: datasets directory missing: {datasets}')
# Default to episodes that the persistent run actually wrote. A -Games 1 run
# must not be misreported as failures for two episodes never requested.
# Explicit seed arguments instead require exactly those episodes to exist.
if len(sys.argv) > 1:
    seeds = [int(x) for x in sys.argv[1:]]
else:
    import re
    seeds = sorted({int(match.group(1)) for f in datasets.glob('batch_prefix_episode_*.jsonl')
                    if (match := re.fullmatch(r'batch_prefix_episode_(\d+)_.*\.jsonl', f.name))})
    if not seeds:
        sys.exit('DIAG_STOP: no persistent episodes found in ai/datasets')
failures = 0
print('BRWR_EXISTING_BATCH_DIAG no_new_games=1 original_game_unchanged=1 checkpoint_unchanged=1')
print(f'EPISODES_AVAILABLE_FOR_DIAG count={len(seeds)} seeds={seeds} (does NOT imply full 3-game parity)')
for seed in seeds:
    ref = sorted(datasets.glob(f'school_prefix_episode_{seed}_*.jsonl'))
    batch = sorted(datasets.glob(f'batch_prefix_episode_{seed}_*.jsonl'))
    if len(ref) != 1 or len(batch) != 1:
        print(f'SEED_{seed} missing/ambiguous files: reference={len(ref)} persistent={len(batch)}')
        failures += 1
        continue
    passed, detail, comp, raw, (records, decisions, ref_end, batch_end) = compare_files(ref[0], batch[0])
    print(f'--- seed={seed} reference={ref[0].name} persistent={batch[0].name}')
    print(f'    equal_record_prefix={records} | equal_transition_prefix={decisions}')
    if raw:
        print(f'    RAW_FIRST_DIFF line={raw[0]} path={raw[1][0]}')
        print(f'      {raw[1][1]}')
    print(f'    Object identity occurrences validated={comp.object_id_occurrences}; distinct mapped={comp.object_id_distinct}')
    print(f'    Candidate hand tokens checked={comp.hand_token_occurrences}; ID differences={comp.hand_token_differences}')
    print(f'    Attack feedback visual coordinates checked={comp.visual_coord_occurrences}; differences={comp.visual_coord_differences}')
    for path, ref_value, batch_value in comp.visual_examples:
        print(f'      ATTACK_VISUAL_COORD_DIFF {path}: ref={ref_value} persistent={batch_value}')
    if passed:
        print(f'    PERSISTENT_SEMANTIC_PARITY_OK all_nonvolatile_fields_equal=1 decisions={decisions}')
        if ref_end is not None:
            print(f'    terminal winner={ref_end.get("winner")} scores={ref_end.get("scores")}')
    else:
        print(f'    PERSISTENT_SEMANTIC_PARITY_FAIL {detail}')
        failures += 1
print('PERSISTENT_EXISTING_DIAG_COMPLETE failures=' + str(failures))
sys.exit(1 if failures else 0)
