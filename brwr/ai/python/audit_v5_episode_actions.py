#!/usr/bin/env python3
"""Read-only forensic summary of an actual BRWR AI episode JSONL.

Does not infer points *caused by* chosen actions: observation snapshots are
pre-decision and score changes may result from other players or Black Rose.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def find_latest():
    files = [p for p in (ROOT / 'ai/datasets').glob('v5_semantic_episode_*.jsonl') if p.is_file()]
    if not files:
        raise FileNotFoundError('No v5 semantic JSONL found. Run R2 with -KeepEpisodes or pass --episode PATH')
    return max(files, key=lambda p: p.stat().st_mtime_ns)


def safe_float(x):
    if x is None or isinstance(x, bool):
        return None
    try:
        y = float(x)
        return y if math.isfinite(y) else None
    except (ValueError, TypeError):
        return None


def chosen_candidate(record):
    target = record.get('selected_candidate_id')
    options = record.get('legal_candidates', [])
    if not isinstance(options, list):
        return None
    return next((x for x in options if isinstance(x, dict) and x.get('id') == target), None)


def action_kind(candidate):
    detail = candidate.get('detail') or {}
    descriptor = detail.get('descriptor') or {}
    action = detail.get('action') or {}
    kind = descriptor.get('kind') or action.get('type') or detail.get('kind')
    return str(kind or 'unknown')


def summarize(path: Path):
    counts = Counter()
    per_player = defaultdict(Counter)
    kinds = Counter()
    kind_by_player = defaultdict(Counter)
    spells = Counter()
    phase_types = Counter()
    action_labels = Counter()
    power_samples = defaultdict(list)
    rose_power_samples = []
    rounds = defaultdict(Counter)
    first, last = None, None
    n_transitions = 0
    missing_candidates = 0
    with path.open('r', encoding='utf-8-sig') as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f'Invalid JSON at line {line_number}: {exc}') from exc
            typ = rec.get('record_type')
            if typ == 'episode_start':
                if first is not None:
                    raise ValueError('Duplicate episode_start')
                first = rec
                continue
            if typ == 'episode_end':
                last = rec
                continue
            if typ != 'transition':
                raise ValueError(f'Unexpected record_type {typ!r} at line {line_number}')
            n_transitions += 1
            request_type = str(rec.get('request_type', 'unknown'))
            player = int(rec['player_index'])
            counts[request_type] += 1
            per_player[player][request_type] += 1
            rounds[int(rec.get('round', -1))][request_type] += 1
            phase_types[(str(rec.get('phase', '')), request_type)] += 1
            candidate = chosen_candidate(rec)
            if candidate is None:
                missing_candidates += 1
            elif request_type == 'action_activation_step':
                kind = action_kind(candidate)
                kinds[kind] += 1
                kind_by_player[player][kind] += 1
                action_labels[str(candidate.get('label', ''))] += 1
                desc = (candidate.get('detail') or {}).get('descriptor') or {}
                spell = desc.get('spell') or {}
                if isinstance(spell, dict) and spell.get('id'):
                    spells[str(spell['id'])] += 1
            obs = rec.get('observation') or {}
            if not isinstance(obs, dict):
                continue
            br = safe_float(obs.get('black_rose_power'))
            if br is not None:
                rose_power_samples.append(br)
            players = obs.get('players', [])
            if isinstance(players, list):
                for idx, pl in enumerate(players):
                    if not isinstance(pl, dict):
                        continue
                    player_id = pl.get('player_index', idx)
                    try:
                        player_id = int(player_id)
                    except (ValueError, TypeError):
                        continue
                    value = safe_float(pl.get('power'))
                    if value is not None:
                        power_samples[player_id].append(value)
    if first is None or last is None or n_transitions == 0:
        raise ValueError('Incomplete episode JSONL; require start, transitions, and end')
    if n_transitions != int(last.get('decisions', -1)):
        raise ValueError('Transition count disagrees with episode_end')
    seed = first.get('seed')
    if seed != last.get('seed'):
        raise ValueError('Start/end seed mismatch')
    bots = int(first.get('human_player_count', 0))
    print('V5_ACTION_AUDIT_READ_ONLY training_updates=0 writes=0')
    print(f'FILE {path.resolve()}')
    print(f'SEED {seed} bots={bots} decisions={n_transitions} rounds={last.get("round")} '
          f'winner={last.get("winner")} missing_chosen_candidates={missing_candidates}')
    print('REQUEST_TYPES ' + ', '.join(f'{k}={v}' for k, v in counts.most_common()))
    print('ACTION_KINDS ' + ', '.join(f'{k}={v}' for k, v in kinds.most_common()))
    print('TOP_SPELL_CAST_OR_MOMENTUM ' + ', '.join(f'{k}={v}' for k, v in spells.most_common(12)))
    print('TOP_ACTIONS ' + ', '.join(f'{k}={v}' for k, v in action_labels.most_common(12)))
    for player in range(bots):
        c = kind_by_player[player]
        print(f'MAGE_{player} action_kinds=' + ', '.join(f'{k}:{v}' for k, v in c.most_common()) +
              ' request_types=' + ', '.join(f'{k}:{v}' for k, v in per_player[player].most_common(8)))
    print('POWER_SNAPSHOTS pre_decision=1 non_causal=1 (not final scoreboard):')
    if rose_power_samples:
        print('  BLACK_ROSE first=%g last=%g max=%g' %
              (rose_power_samples[0], rose_power_samples[-1], max(rose_power_samples)))
    for idx in range(bots):
        samples = power_samples.get(idx, [])
        if samples:
            print('  MAGE_%d first=%g last=%g max=%g increases=%d decreases=%d' %
                  (idx, samples[0], samples[-1], max(samples),
                   sum(y > x for x,y in zip(samples, samples[1:])),
                   sum(y < x for x,y in zip(samples, samples[1:]))))
    print('FINAL_SCORE_COMPONENTS:')
    scores = last.get('scores', [])
    for item in sorted(scores, key=lambda x: int(x.get('player_index', 99))):
        print('  index=%s name=%s total=%s base=%s quests=%s trophies=%s crown=%s' %
              (item.get('player_index'), item.get('name'), item.get('total'),
               item.get('base'), item.get('quests'), item.get('trophies'), item.get('crown')))
    print('NOTE: This report counts chosen actions and observed power snapshots; '
          'it does not establish causality or assess legality/strategic quality.')
    print('V5_ACTION_AUDIT_COMPLETE')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--episode', type=Path, default=None,
                    help='Actual JSONL; if absent, selects newest v5_semantic_episode_*.jsonl')
    args = ap.parse_args()
    path = args.episode or find_latest()
    if not path.is_file():
        ap.error('Episode does not exist: ' + str(path))
    summarize(path)


if __name__ == '__main__':
    main()
