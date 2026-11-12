"""Small, strictly local penalty for selecting a Momentum ACTION in BRWR.

Not a terminal punishment: does not alter final score, Black Rose margin,
peer margin, or historical baseline. It is applied only to the log probability
of the exact decision that selected a momentum action.
"""
from __future__ import annotations

PENALTY = -0.003
VERSION = 'v5_r3_momentum_local_minus_0003_v1'


def selected_momentum_penalties(transitions: list[dict], bots: int) -> tuple[dict[int,float],dict]:
    penalties: dict[int,float] = {}
    alternative_casts = 0
    total_actions = 0
    for expected_step, record in enumerate(transitions, 1):
        if not isinstance(record, dict) or record.get('record_type') != 'transition':
            raise ValueError('Unexpected record where transition is expected')
        if record.get('step') != expected_step:
            raise ValueError('Decision steps must be consecutive from 1')
        idx = record.get('player_index')
        if not isinstance(idx, int) or not 0 <= idx < bots:
            raise ValueError('Unexpected transition player index')
        if record.get('request_type') != 'action_activation_step':
            continue
        total_actions += 1
        candidates = record.get('legal_candidates')
        if not isinstance(candidates, list):
            raise ValueError('Action decision missing candidate list')
        chosen_id = record.get('selected_candidate_id')
        matches = [c for c in candidates if isinstance(c,dict) and c.get('id') == chosen_id]
        if len(matches) != 1:
            raise ValueError('Action decision lacks a unique selected candidate')
        chosen_detail = matches[0].get('detail')
        if not isinstance(chosen_detail, dict):
            raise ValueError('Selected action lacks a detail object')
        descriptor = chosen_detail.get('descriptor', {})
        action = chosen_detail.get('action', {})
        if not isinstance(descriptor, dict) or not isinstance(action,dict):
            raise ValueError('Action decision has unexpected descriptor/action')
        descriptor_kind = descriptor.get('kind')
        action_type = action.get('type')
        # Require both fields to agree. A label such as "Momentum" is not
        # sufficient evidence. Never punish a preparation discard or a choice
        # made during spell resolution.
        if (descriptor_kind == 'momentum') != (action_type == 'momentum'):
            raise ValueError('Conflicting momentum identifiers in selected action')
        if descriptor_kind == 'momentum' and action_type == 'momentum':
            penalties[expected_step] = PENALTY
            if any(
                isinstance(c, dict)
                and isinstance(c.get('detail'),dict)
                and isinstance(c['detail'].get('descriptor'),dict)
                and c['detail']['descriptor'].get('kind') == 'cast'
                for c in candidates
            ):
                alternative_casts += 1
    return penalties, {
        'momentum_actions': len(penalties),
        'with_cast_alternative': alternative_casts,
        'action_decisions': total_actions,
        'total_penalty': sum(penalties.values()),
    }
