"""Strict parser for AI-only, causally attributed R3 effective-spell receipts.

Receipts are produced by instrumented GDScript immediately at a concrete
state-change boundary. This parser NEVER interprets a cast or generic
'effect_resolved' log as success.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import v5_reward_v3 as reward

SCHEMA = 'brwr_v5_r3_effect_receipts_v1'


def _is_cast_action(transition: dict) -> bool:
    index = int(transition['selected_candidate_id'])
    candidate = transition['legal_candidates'][index]
    detail = candidate.get('detail', {})
    if not isinstance(detail, dict):
        return False
    action = detail.get('action', {})
    descriptor = detail.get('descriptor', {})
    return (
        str(descriptor.get('kind', '')) == 'cast'
        or str(action.get('type', '')) in ('spell', 'quick')
    )


def load_effect_bonuses(path: Path, *, seed: int, decisions: int,
                        transitions: list[dict], bots: int) -> tuple[dict[int, float], dict]:
    if len(transitions) != decisions:
        raise ValueError('R3 transition length mismatch')
    if not path.is_file():
        raise ValueError('R3 receipt missing: ' + str(path))
    document = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(document, dict) or document.get('schema') != SCHEMA:
        raise ValueError('R3 receipts schema invalid')
    if int(document.get('seed', -1)) != seed or int(document.get('decisions', -1)) != decisions:
        raise ValueError('R3 receipts seed or decision count differs from episode')
    events = document.get('events')
    if not isinstance(events, list):
        raise ValueError('R3 receipts events must be a list')
    uncredited = int(document.get('uncredited', -1))
    if uncredited < 0:
        raise ValueError('R3 uncredited must be nonnegative')
    per_step: dict[int, float] = {}
    counts = {'spell': 0, 'reaction': 0}
    for ix, event in enumerate(events):
        if not isinstance(event, dict):
            raise ValueError(f'R3 event {ix} invalid')
        step = int(event.get('step', -1))
        owner = int(event.get('player_index', -1))
        kind = event.get('kind')
        if kind not in counts or not (1 <= step <= decisions) or not (0 <= owner < bots):
            raise ValueError(f'R3 event {ix} has bad kind/step/owner')
        if not str(event.get('spell_id', '')):
            raise ValueError(f'R3 event {ix} missing spell identity')
        if not (event.get('material_change') is True or event.get('prevention') is True):
            raise ValueError(f'R3 event {ix} lacks a concrete effect proof')
        if kind == 'reaction' and event.get('spell_type') not in ('trap', 'protection'):
            raise ValueError('R3 reaction type must be trap/protection')
        source = transitions[step - 1]
        if int(source['step']) != step or int(source['player_index']) != owner or not _is_cast_action(source):
            raise ValueError(f'R3 event {ix}: cast decision attribution invalid at step {step}')
        value = reward.REACTION_EFFECT_BONUS if kind == 'reaction' else reward.SPELL_EFFECT_BONUS
        per_step[step] = per_step.get(step, 0.0) + value
        counts[kind] += 1
    # The aggregate cap prevents one repeating permanent from making shaping
    # dominate the points objective. No hidden extra reward is introduced.
    cap = 0.04
    per_step = {step: min(cap, value) for step, value in per_step.items()}
    if not all(math.isfinite(v) for v in per_step.values()):
        raise ValueError('R3 bonus nonfinite')
    summary = {
        'effective_spells': counts['spell'],
        'effective_reactions': counts['reaction'],
        'uncredited': uncredited,
        'credited_decisions': len(per_step),
        'bonus_sum': sum(per_step.values()),
    }
    return per_step, summary
