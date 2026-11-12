#!/usr/bin/env python3
"""Read-only audit of the existing BRWR V5 Momentum-One checkpoint/history.

Does not train, import project game modules, alter policy parameters, or mutate
existing artifacts.  Writes only the requested human-readable audit report.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = ROOT / 'ai/model/brwr_policy_v5_momentumone_reset.pt'
HISTORY = ROOT / 'ai/model/training_history_v5_momentumone_reset.csv'
DATASETS = ROOT / 'ai/datasets'


def number(row: dict, key: str) -> float | None:
    try:
        n = float(row[key])
        return n if math.isfinite(n) else None
    except (KeyError, TypeError, ValueError):
        return None


def avg(rows: list[dict], key: str):
    valid = [value for row in rows if (value := number(row, key)) is not None]
    return sum(valid) / len(valid) if valid else None


def fmt(num, decimals=3) -> str:
    return 'n/a' if num is None else f'{num:.{decimals}f}'


def read_checkpoint() -> dict:
    import torch
    if not CHECKPOINT.is_file():
        raise RuntimeError(f'Checkpoint missing: {CHECKPOINT}')
    cp = torch.load(CHECKPOINT, map_location='cpu', weights_only=False)
    if cp.get('experiment') != 'v5_momentumone_reset_random_v1':
        raise RuntimeError('Different checkpoint experiment: ABORT')
    return cp


def load_history() -> list[dict]:
    if not HISTORY.is_file():
        return []
    with HISTORY.open('r', encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if not {'v5m1_game', 'best_margin_vs_rose', 'updated_weights'}.issubset(reader.fieldnames or []):
            raise RuntimeError('Unexpected V5M1 history schema')
        return list(reader)


def episode_game(path: Path):
    # Default seed = 20350101 + game number in this isolated experiment.
    name = path.name
    prefix = 'v5_semantic_episode_'
    if not name.startswith(prefix):
        return None
    try:
        return int(name[len(prefix):].split('_', 1)[0]) - 20350101
    except (IndexError, ValueError):
        return None


def selected_detail(record: dict) -> dict | None:
    opts = record.get('legal_candidates')
    idx = record.get('selected_candidate_id')
    if not isinstance(opts, list) or not isinstance(idx, int) or not 0 <= idx < len(opts):
        return None
    candidate = opts[idx]
    if not isinstance(candidate, dict):
        return None
    detail = candidate.get('detail')
    return detail if isinstance(detail, dict) else None


def kind_from_record(record: dict) -> str:
    detail = selected_detail(record)
    if detail is None:
        return 'unknown'
    descriptor = detail.get('descriptor', {})
    action = detail.get('action', {})
    if isinstance(descriptor, dict) and descriptor.get('kind') == 'cast':
        return 'cast'
    if isinstance(action, dict) and action.get('type') in ('spell', 'quick'):
        return 'cast'
    if isinstance(descriptor, dict):
        kind = descriptor.get('kind')
        if isinstance(kind, str) and kind:
            return kind
    if isinstance(action, dict):
        kind = action.get('type')
        if isinstance(kind, str) and kind:
            return kind
    return 'unknown'


def inspect_episode(path: Path) -> dict:
    selected = Counter()
    action_steps = 0
    steps = {}
    seed = None
    decisions = None
    with path.open('r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get('record_type') == 'episode_start':
                seed = record.get('seed')
            elif record.get('record_type') == 'episode_end':
                decisions = record.get('decisions')
            elif record.get('record_type') == 'transition' and record.get('request_type') == 'action_activation_step':
                action_steps += 1
                kind = kind_from_record(record)
                selected[kind] += 1
                steps[record.get('step')] = (record.get('player_index'), kind,
                    (selected_detail(record) or {}).get('descriptor', {}))
    events, mismatched, missing = 0, [], False
    receipt = Path(str(path) + '.r3_receipts.json')
    if not receipt.is_file():
        missing = True
    else:
        doc = json.loads(receipt.read_text(encoding='utf-8'))
        if seed is not None and doc.get('seed') != seed:
            mismatched.append('receipt seed mismatch')
        if decisions is not None and doc.get('decisions') != decisions:
            mismatched.append('receipt decisions mismatch')
        for i, ev in enumerate(doc.get('events', [])):
            events += 1
            if not isinstance(ev, dict):
                mismatched.append(f'event[{i}] not mapping')
                continue
            info = steps.get(ev.get('step'))
            if info is None:
                mismatched.append(f'event[{i}] step {ev.get("step")} not action step')
                continue
            owner, kind, desc = info
            if owner != ev.get('player_index'):
                mismatched.append(f'event[{i}] player mismatch')
            origin = ev.get('cast_origin', 'direct')
            if origin == 'direct':
                spell = desc.get('spell', {}) if isinstance(desc, dict) else {}
                if kind != 'cast' or not isinstance(spell, dict) or spell.get('id') != ev.get('spell_id'):
                    mismatched.append(f'event[{i}] direct cast identity/step mismatch ({kind}, {ev.get("spell_id")})')
                if isinstance(ev.get('use_dark_side'), bool) and isinstance(spell, dict) and ev['use_dark_side'] != spell.get('use_dark_side'):
                    mismatched.append(f'event[{i}] spell side mismatch')
            elif origin == 'room_cast_next_ready':
                if kind not in ('explore', 'fight') or not ev.get('origin_room_id'):
                    mismatched.append(f'event[{i}] invalid room auto cast source')
            else:
                mismatched.append(f'event[{i}] unknown origin {origin}')
    return {'game': episode_game(path), 'name': path.name, 'action_steps': action_steps,
            'counts': selected, 'receipt_events': events, 'errors': mismatched,
            'missing_receipts': missing}


def report(checkpoint: dict, history: list[dict], episode_limit: int) -> str:
    done = int(checkpoint['games_completed'])
    text = []
    add = text.append
    add('BRWR V5-MOMENTUM-ONE — READ-ONLY TRAINING AUDIT')
    add('Generated ' + datetime.now().isoformat(timespec='seconds'))
    add('No checkpoint, model, training history or episode was modified.')
    add('')
    add('CHECKPOINT')
    for key in ('experiment', 'games_completed', 'random_reset_seed', 'reward_version',
                'group_policy_version', 'baseline_version', 'momentum_penalty'):
        add(f'  {key}: {checkpoint.get(key)}')
    add(f'  size_bytes: {CHECKPOINT.stat().st_size}')
    add(f'  modified: {datetime.fromtimestamp(CHECKPOINT.stat().st_mtime).isoformat(timespec="seconds")}')
    add('')
    add('TRAINING HISTORY')
    add(f'  history_rows={len(history)}, checkpoint_games={done}')
    if history:
        nums = [int(r['v5m1_game']) for r in history]
        add(f'  contiguous_games={nums == list(range(1, len(nums) + 1))}')
        add(f'  history_matches_checkpoint={len(history) == done and nums[-1] == done}')
        add(f'  updated_weights_count={sum(r.get("updated_weights") == "1" for r in history)}')
        add('  windows (means, not controlled evaluations; scenarios differ):')
        for lo in range(1, done + 1, 25):
            subset = [r for r in history if lo <= int(r['v5m1_game']) <= lo+24]
            if not subset:
                continue
            add(f'    games={lo}-{min(lo+24, done)} n={len(subset)} '
                f'best_margin={fmt(avg(subset, "best_margin_vs_rose"))} '
                f'best_mage={fmt(avg(subset, "best_mage_score"))} '
                f'rose={fmt(avg(subset, "rose_score"))} '
                f'momentum/game={fmt(avg(subset, "momentum_actions"))} '
                f'effective_spells/game={fmt(avg(subset, "effective_spell_resolutions"))} '
                f'updated={sum(r.get("updated_weights") == "1" for r in subset)}/{len(subset)}')
    add('')
    episodes = []
    for path in DATASETS.glob('v5_semantic_episode_2035*.jsonl'):
        n = episode_game(path)
        if n is not None and 1 <= n <= done:
            episodes.append((n, path))
    episodes.sort(key=lambda item: item[0])
    # Keep the default run light: the complete retained dataset is several GB.
    if episode_limit > 0:
        selected_eps = episodes[-episode_limit:]
    else:
        selected_eps = episodes
    add('EPISODE AUDIT')
    add(f'  retained_completed_episode_files={len(episodes)}')
    add(f'  files_selected_for_readonly_check={len(selected_eps)}')
    totals = Counter()
    errors = []
    missing = []
    total_steps = 0
    total_events = 0
    for n, path in selected_eps:
        try:
            ev = inspect_episode(path)
            total_steps += ev['action_steps']
            total_events += ev['receipt_events']
            totals.update(ev['counts'])
            errors.extend(f'game {n}: {msg}' for msg in ev['errors'])
            if ev['missing_receipts']:
                missing.append(n)
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
            errors.append(f'game {n}: could not inspect: {type(exc).__name__} {exc}')
    add(f'  action_steps_inspected={total_steps} receipts_inspected={total_events}')
    if total_steps:
        add('  selected actions: ' + ', '.join(
            f'{k}={v} ({100*v/total_steps:.1f}%)' for k,v in sorted(totals.items())))
    add(f'  missing_receipts_games={missing}')
    add(f'  potential_receipt_attribution_errors={len(errors)}')
    for msg in errors[:35]:
        add('    ' + msg)
    if len(errors) > 35:
        add(f'    ... and {len(errors)-35} more')
    add('')
    add('INTERPRETATION')
    add('  This is a historical data-quality check, not proof that the AI is stronger.')
    add('  Raw win rates and action mixes across varying scenarios are not a controlled benchmark.')
    add('  Pre-fix receipts may lack explicit cast origin and side metadata.')
    add('  All changes to reward design are intentionally deferred.')
    return '\n'.join(text) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--checkpoint-games', action='store_true',
                    help='Print only checkpoint games_completed (for safe PowerShell guard)')
    ap.add_argument('--recent-episodes', type=int, default=12,
                    help='Recent completed retained episodes to inspect; 0 means ALL, default 12')
    ap.add_argument('--output', type=Path,
                    default=ROOT / 'v5m1_training_audit.txt')
    args = ap.parse_args()
    if args.recent_episodes < 0:
        raise SystemExit('recent-episodes must be >=0')
    cp = read_checkpoint()
    if args.checkpoint_games:
        print(int(cp['games_completed']))
        return
    history = load_history()
    result = report(cp, history, args.recent_episodes)
    args.output.write_text(result, encoding='utf-8')
    print(result)
    print('V5M1_AUDIT_SAVED ' + str(args.output))


if __name__ == '__main__':
    main()
