#!/usr/bin/env python3
"""Read-only diagnostics for V5 Momentum-One failed R3 receipt attribution.

No training, overwrites or source modifications. Produces a small text report.
"""
from __future__ import annotations

import collections
import datetime
import json
from pathlib import Path
import sys
import traceback

ROOT = Path(__file__).resolve().parents[2]
EPISODE_NAME = 'v5_semantic_episode_20350232_h5_avpossessed_apprentice_normal.jsonl'
EPISODE = ROOT / 'ai' / 'datasets' / EPISODE_NAME
RECEIPTS = Path(str(EPISODE) + '.r3_receipts.json')
VALIDATOR = ROOT / 'ai' / 'python' / 'v5_r3_effect_receipts.py'
MODEL = ROOT / 'ai' / 'model' / 'brwr_policy_v5_momentumone_reset.pt'
REPORT = ROOT / 'v5m1_game131_attribution_diagnostic.txt'
TARGET_STEP = 416

lines: list[str] = []


def say(s=''):
    lines.append(str(s))


def excerpt(value, n=3500):
    try:
        out = json.dumps(value, ensure_ascii=False, indent=2, default=str)
    except Exception:
        out = repr(value)
    return out if len(out) < n else out[:n] + '\n... [truncated for brevity]'


def summarize_transition(t):
    if not isinstance(t, dict):
        return excerpt(t, 1000)
    keys = ('step', 'player_index', 'request_type', 'selected_candidate_id',
            'selected', 'action_kind', 'kind', 'event', 'action_type', 'label')
    base = {k: t.get(k) for k in keys if k in t}
    choices = t.get('legal_candidates', [])
    if isinstance(choices, list):
        base['legal_candidates_count'] = len(choices)
        counts = collections.Counter(
            str(c.get('action_kind', c.get('kind', c.get('category', c.get('type', '?')))))
            if isinstance(c, dict) else str(type(c).__name__)
            for c in choices)
        base['legal_candidate_kinds'] = dict(counts)
        selected = t.get('selected_candidate_id', t.get('selected'))
        selected_choices = [c for i, c in enumerate(choices)
                            if (isinstance(c, dict) and any(c.get(k) == selected
                                for k in ('id', 'candidate_id', 'action_id'))) or i == selected]
        base['selected_legal_candidates'] = selected_choices[:3]
    return excerpt(base, 2500)


def step_equals(value, target=TARGET_STEP):
    if isinstance(value, dict):
        for k, v in value.items():
            if ('step' in k.lower() or k.lower() in ('action_index','decision')) and v == target:
                return True
        return False
    return False


def walk(obj, name='$', depth=0):
    if depth > 7:
        return
    if isinstance(obj, dict):
        yield name, obj
        for k, v in obj.items():
            if isinstance(v, (dict, list)):
                yield from walk(v, name + '.' + str(k), depth + 1)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            if isinstance(v, (dict, list)):
                yield from walk(v, name + '[%d]' % i, depth + 1)


def main():
    say('V5 Momentum-One | R3 receipt attribution failure diagnostic')
    say('Created: ' + datetime.datetime.now().isoformat(timespec='seconds'))
    say('READ-ONLY: No models, episodes or source files were modified.')
    say('Target: game 131, seed 20350232, receipt event 12, step 416')
    say()
    try:
        if MODEL.exists():
            say('CHECKPOINT: %s | bytes=%d | mtime=%s' %
                (MODEL, MODEL.stat().st_size, datetime.datetime.fromtimestamp(MODEL.stat().st_mtime)))
            try:
                import torch
                model = torch.load(MODEL, map_location='cpu', weights_only=False)
                say('CHECKPOINT games_completed=%r experiment=%r reward_version=%r' %
                    (model.get('games_completed'), model.get('experiment'), model.get('reward_version')))
            except Exception as exc:
                say('CHECKPOINT_METADATA_ERROR: %s: %s' % (type(exc).__name__, exc))
        else:
            say('CHECKPOINT_MISSING: ' + str(MODEL))
        say()
        if not EPISODE.exists():
            say('EPISODE_MISSING: ' + str(EPISODE))
        else:
            say('EPISODE bytes=%d mtime=%s' %
                (EPISODE.stat().st_size, datetime.datetime.fromtimestamp(EPISODE.stat().st_mtime)))
            transitions = []
            near_events = []
            n_records = 0
            with EPISODE.open('r', encoding='utf-8') as f:
                for line_number, line in enumerate(f, 1):
                    if not line.strip():
                        continue
                    n_records += 1
                    try:
                        obj = json.loads(line)
                    except Exception as exc:
                        say('INVALID_JSON_AT_LINE %d: %s' % (line_number, exc))
                        continue
                    if not isinstance(obj, dict):
                        continue
                    if obj.get('record_type') == 'transition':
                        transitions.append(obj)
                    elif step_equals(obj) and len(near_events) < 8:
                        near_events.append((line_number, obj))
            say('EPISODE parsed_records=%d transition_count=%d' % (n_records, len(transitions)))
            say('TRANSITIONS NEAR STEP 416:')
            for pos, t in enumerate(transitions):
                if t.get('step') in range(TARGET_STEP - 3, TARGET_STEP + 4) or (pos + 1) in range(TARGET_STEP - 3, TARGET_STEP + 4):
                    say('  transition_index=%d | %s' % (pos + 1, summarize_transition(t)))
            say('LAST 12 SELECTED CASTS PRECEDING STEP 416:')
            count = 0
            for i in range(len(transitions) - 1, -1, -1):
                t = transitions[i]
                if t.get('step', i + 1) > TARGET_STEP:
                    continue
                sel = summarize_transition(t).lower()
                if 'cast' in sel and ('"selected_legal_candidates"' in sel or '"kind"' in sel):
                    say('  index=%d | %s' % (i + 1, summarize_transition(t)))
                    count += 1
                    if count >= 12:
                        break
            say('NON-TRANSITION RECORDS MENTIONING STEP 416:')
            for lineno, obj in near_events:
                say('  line=%d | %s' % (lineno, excerpt(obj, 1500)))
        say()
        if not RECEIPTS.exists():
            say('RECEIPTS_MISSING: ' + str(RECEIPTS))
        else:
            say('RECEIPTS bytes=%d mtime=%s' %
                (RECEIPTS.stat().st_size, datetime.datetime.fromtimestamp(RECEIPTS.stat().st_mtime)))
            receipts_data = json.loads(RECEIPTS.read_text(encoding='utf-8'))
            say('RECEIPTS ROOT:')
            if isinstance(receipts_data, dict):
                say(excerpt({k: v for k, v in receipts_data.items() if not isinstance(v, (list, dict))}, 3000))
                say('LIST LENGTHS: ' + excerpt({k: len(v) for k, v in receipts_data.items() if isinstance(v, list)}, 1000))
            else:
                say('type=%s count=%s' % (type(receipts_data).__name__, len(receipts_data) if hasattr(receipts_data, '__len__') else '?'))
            say('RECEIPT EVENT 12 (both 1-based and 0-based indexing), AND EVENTS CLAIMING STEP 416:')
            seen = set()
            listed = 0
            for path, obj in walk(receipts_data):
                if not isinstance(obj, dict):
                    continue
                index_match = path.endswith('[11]') or path.endswith('[12]')
                id_match = obj.get('event_id') == 12 or obj.get('event_index') == 12 or obj.get('id') == 12
                if step_equals(obj) or index_match or id_match:
                    if path in seen:
                        continue
                    seen.add(path)
                    say('  %s: %s' % (path, excerpt(obj, 4500)))
                    listed += 1
                    if listed >= 25:
                        say('  [more omitted]')
                        break
            if not listed:
                say('No matching dictionary in receipts. Full receipts (small file):')
                say(excerpt(receipts_data, 10000))
        say()
        if VALIDATOR.exists():
            source = VALIDATOR.read_text(encoding='utf-8').splitlines()
            matches = [i for i, line in enumerate(source) if 'cast decision attribution invalid' in line]
            say('VALIDATOR SOURCE: %s | lines=%d | attribution_error_occurrences=%d' %
                (VALIDATOR, len(source), len(matches)))
            for i in matches:
                say('VALIDATOR CODE AROUND LINE %d:' % (i + 1))
                for j in range(max(0, i - 32), min(len(source), i + 18)):
                    say(' %4d | %s' % (j + 1, source[j]))
            if not matches:
                say('Warning: error text not found in validator source; check imports.')
        else:
            say('VALIDATOR_MISSING: ' + str(VALIDATOR))
    except Exception:
        say('DIAGNOSTIC_INTERNAL_ERROR:')
        say(traceback.format_exc())
    REPORT.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('V5M1_DIAGNOSTIC_SAVED ' + str(REPORT))
    print('V5M1_DIAGNOSTIC_END (checkpoint and training unchanged)')

if __name__ == '__main__':
    main()
