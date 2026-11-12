#!/usr/bin/env python3
"""READ-ONLY validation of all 20 receipts from the already-failed Game 399."""
from __future__ import annotations
import json
import sys
from pathlib import Path
import v5m1_effect_receipts as receipts

PROJECT = Path(__file__).resolve().parents[2]
DATA = PROJECT / 'ai/datasets'
FILENAME = 'v5_semantic_episode_20350500_h4_avpossessed_master_normal.jsonl'
SEED = 20350500


def main() -> int:
    episode = DATA / FILENAME
    receipt_path = Path(str(episode) + '.r3_receipts.json')
    if not episode.is_file() or not receipt_path.is_file():
        print('V5M1_GAME399_AUDIT_STOP missing original episode/receipts; cannot validate without them')
        print(f'  episode={episode}')
        print(f'  receipts={receipt_path}')
        return 2
    transitions = []
    with episode.open('r', encoding='utf-8') as stream:
        for line in stream:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get('record_type') == 'transition':
                transitions.append(record)
    document = json.loads(receipt_path.read_text(encoding='utf-8'))
    events = document.get('events', [])
    if document.get('seed') != SEED or document.get('decisions') != len(transitions):
        raise ValueError('Game399 seed/decision mismatch')
    if len(events) != 20:
        raise ValueError(f'Game399 expected 20 receipts; found {len(events)}')
    target = events[7]
    if not all((target.get('kind') == 'reaction',
                target.get('spell_id') == 'sarcophagus',
                target.get('spell_type') == 'protection',
                target.get('player_index') == 3, target.get('step') == 157)):
        raise ValueError('Game399 event[7] differs from investigated receipt')
    if not (len(transitions) >= 157
            and transitions[156].get('player_index') == 3):
        raise ValueError('Game399 source decision at step157 changed')
    bonuses, summary = receipts.load_effect_bonuses(
        receipt_path, seed=SEED, decisions=len(transitions),
        transitions=transitions, bots=4)
    if 157 not in bonuses:
        raise ValueError('Game399 Sarcophagus receipt was not credited to choice at 157')
    print('V5M1_GAME399_AUDIT_OK read_only=1')
    print('  episode_decisions=%d receipts=%d reaction_selection_confirmed=%d' %
          (len(transitions), len(events), summary['reaction_card_selections']))
    print('  sarcophagus_reaction_step=157 owner=3 bonus=%.6f' % bonuses[157])
    print('  total_bonus=%.6f credited_decisions=%d uncredited=%d' %
          (summary['bonus_sum'],summary['credited_decisions'],summary['uncredited']))
    print('  full_episode_receipts_validated=1 checkpoint_untouched=1')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('V5M1_GAME399_AUDIT_STOP %s: %s' % (type(exc).__name__,exc))
        sys.exit(1)
