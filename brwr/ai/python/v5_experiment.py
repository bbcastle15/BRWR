"""Read-only v5 feature audit; optional isolated checkpoint initialization.

No Godot simulation; no training; never changes ai/model/brwr_policy_v4.pt.
"""
from __future__ import annotations
import argparse
import collections
import csv
import hashlib
import json
import math
import sys
from pathlib import Path

import torch
from torch import nn

import train as v4
import v5_encoder as v5

ROOT = Path(__file__).resolve().parents[2]
V4_CHECKPOINT = ROOT / 'ai/model/brwr_policy_v4.pt'
V5_INIT = ROOT / 'ai/model/brwr_policy_v5_init.pt'
FIXTURE = ROOT / 'ai/python/v5_real_decision_samples.jsonl'


class V5Policy(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(nn.Linear(v5.FEATURE_DIM, 96), nn.Tanh(),
                                 nn.Linear(96, 48), nn.Tanh(), nn.Linear(48, 1))

    def forward(self, features):
        return self.net(features).flatten()


def _features(v: list[float], omit_index: bool = True) -> tuple[float, ...]:
    if omit_index:
        v[17] = 0.0
    return tuple(round(x, 6) for x in v)


def audit_episode(path: Path, max_decisions: int = 100000) -> tuple[dict, list[dict]]:
    stats = collections.defaultdict(lambda: [0, 0, 0, 0, 0, 0])
    examples = []
    with path.open('r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get('record_type') != 'transition':
                continue
            choices = row.get('legal_candidates', [])
            if not isinstance(choices, list) or len(choices) < 2:
                continue
            obs = row['observation']
            d = {'player_index': row['player_index'], 'type': row.get('request_type', ''),
                 'substep': row.get('substep', '') or ''}
            kind = str(d['type'])
            v4_unique = set()
            semantic_unique = set()
            for idx, candidate in enumerate(choices):
                old = v4.encode_action(obs, d, candidate, idx, len(choices))
                v4_unique.add(_features(old))
                semantic_unique.add(_features(v5.semantic_features(obs, d, candidate), omit_index=False))
            s = stats[kind]
            s[0] += 1
            s[1] += len(choices)
            s[2] += len(v4_unique)
            s[3] += len(semantic_unique)
            s[4] += int(len(v4_unique) == 1)
            s[5] += int(len(semantic_unique) == 1)
            if len(semantic_unique) < len(choices) and len(examples) < 8:
                examples.append({'type': kind, 'candidates': len(choices),
                                 'distinct_semantic_vectors': len(semantic_unique),
                                 'step': row.get('step')})
            max_decisions -= 1
            if max_decisions <= 0:
                break
    return dict(stats), examples


def prepare_godot_probe(path: Path, out: Path, max_cases: int = 24) -> int:
    cases = []
    with path.open('r', encoding='utf-8') as f:
        for line in f:
            row = json.loads(line)
            if row.get('record_type') != 'transition':
                continue
            choices = row.get('legal_candidates', [])
            if not isinstance(choices, list) or len(choices) < 2:
                continue
            obs = row['observation']
            decision = {'player_index': row['player_index'], 'type': row.get('request_type', ''),
                        'substep': row.get('substep', '') or ''}
            for i in (0, len(choices)-1):
                c = choices[i]
                cases.append({'observation': obs, 'decision': decision,
                              'option': c, 'index': i, 'total_options': len(choices),
                              'expected_features': v5.semantic_features(obs, decision, c)})
                if len(cases) >= max_cases:
                    break
            if len(cases) >= max_cases:
                break
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({'encoder_version': v5.ENCODER_VERSION, 'cases': cases},
                              separators=(',', ':'), ensure_ascii=False), encoding='utf-8')
    return len(cases)


def initialize_checkpoint() -> None:
    if not V4_CHECKPOINT.is_file():
        raise RuntimeError('Missing v4 checkpoint: no random fallback allowed')
    if V5_INIT.exists():
        raise RuntimeError(f'v5 initialization already exists: {V5_INIT}; refusing overwrite')
    chk = torch.load(V4_CHECKPOINT, map_location='cpu', weights_only=False)
    if chk.get('feature_dim') != v5.V4_DIM or int(chk.get('games_completed', -1)) < 500:
        raise RuntimeError('Unexpected v4 checkpoint dimension or number of games; stop')
    old = v4.ActionPolicy()
    old.load_state_dict(chk['model'])
    new = V5Policy()
    with torch.no_grad():
        new.net[0].weight.zero_()
        new.net[0].weight[:, :v5.V4_DIM].copy_(old.net[0].weight)
        new.net[0].bias.copy_(old.net[0].bias)
        for n in (2, 4):
            new.net[n].weight.copy_(old.net[n].weight)
            new.net[n].bias.copy_(old.net[n].bias)
    # New semantic inputs start at zero influence: same initial outputs, then learnable.
    sample = torch.randn(64, v5.V4_DIM)
    extended = torch.cat((sample, torch.randn(64, v5.SEMANTIC_DIM)), dim=-1)
    with torch.no_grad():
        diff = (old(sample)-new(extended)).abs().max().item()
    if diff > 1e-5:
        raise RuntimeError(f'Unsafe warmstart: max old-vs-new score error={diff}')
    # New Adam optimizer is intentional: old momentum tensors have incompatible dimensions.
    opt = torch.optim.Adam(new.parameters(), lr=0.0005)
    payload = {'model': new.state_dict(), 'optimizer': opt.state_dict(),
               'games_completed': 0, 'feature_dim': v5.FEATURE_DIM,
               'encoder_version': v5.ENCODER_VERSION,
               'initialized_from_v4_games': int(chk['games_completed']),
               'v4_checkpoint_sha256': hashlib.sha256(V4_CHECKPOINT.read_bytes()).hexdigest(),
               'note': 'Initialization only; no v5 training has happened.'}
    V5_INIT.parent.mkdir(parents=True, exist_ok=True)
    tmp = V5_INIT.with_name(V5_INIT.name + '.tmp')
    torch.save(payload, tmp)
    tmp.replace(V5_INIT)
    print(f'V5_CHECKPOINT_INITIALIZED path={V5_INIT} games_trained_v5=0 '
          f'from_v4={chk["games_completed"]} v4_score_max_diff={diff:.3g} '
          f'optimizer_reset=1 original_v4_unchanged=1')


def main():
    ap = argparse.ArgumentParser(description='BRWR v5 semantic encoder (audit only)')
    ap.add_argument('--episode', type=Path, help='Existing JSONL file for real-world audit; optional')
    ap.add_argument('--init-v5', action='store_true', help='Create separate v5 initialization, never train')
    ap.add_argument('--probe', action='store_true', help='Write tiny Godot semantic-feature parity probe')
    args = ap.parse_args()
    path = args.episode
    if path is None:
        candidates = [p for p in (ROOT / 'ai/datasets').glob('*.jsonl') if p.is_file()]
        path = max(candidates, key=lambda p: p.stat().st_mtime) if candidates else FIXTURE
        if path == FIXTURE:
            print('AUDIT_SOURCE bundled_real_decision_samples (not current policy500 episode)')
    if not path.is_file():
        ap.error(f'Episode missing: {path}')
    print(f'V5_AUDIT_INPUT {path}')
    stats, examples = audit_episode(path)
    print('TYPE | decisions | options | v4_unique_except_index | v5_semantic_unique | all-v4-identical | all-v5-identical')
    for k, s in sorted(stats.items(), key=lambda pair: -pair[1][0]):
        print(k + ' | ' + ' | '.join(map(str, s)))
    if examples:
        print('SEMANTIC_AMBIGUITIES examples=' + json.dumps(examples, separators=(',', ':')))
    print('V5_AUDIT_COMPLETE no_godot_runs=1 no_training=1 checkpoint_v4_untouched=1')
    if args.probe:
        out = ROOT / 'ai/model/v5_encoder_probe.json'
        n = prepare_godot_probe(path, out)
        print(f'V5_ENCODER_PROBE_WRITTEN path={out} cases={n}')
    if args.init_v5:
        initialize_checkpoint()


if __name__ == '__main__':
    main()
