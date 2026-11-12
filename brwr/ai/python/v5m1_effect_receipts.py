"""Strict V5-MOMENTUM-ONE receipt parser with proven room-auto-cast support.

NEVER credit non-Cast actions from only a same-player/same-step receipt.
Room-generated Cast provenance comes from the nested Godot room-effect stack,
and is checked against the corresponding room-activating player action.
Other R3 trainers retain their original parser.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import v5_reward_v3 as reward

SCHEMA = 'brwr_v5_r3_effect_receipts_v1'


def _selected_detail(transition: dict) -> dict:
    options = transition.get('legal_candidates')
    index = int(transition.get('selected_candidate_id', -1))
    if not isinstance(options, list) or not (0 <= index < len(options)):
        raise ValueError('R3 selected candidate missing/invalid')
    candidate = options[index]
    if not isinstance(candidate, dict):
        raise ValueError('R3 selected candidate not a mapping')
    detail = candidate.get('detail', {})
    if not isinstance(detail, dict):
        raise ValueError('R3 selected candidate detail invalid')
    return detail


def _direct_cast_matches(source: dict, event: dict) -> bool:
    if source.get('request_type') != 'action_activation_step':
        return False
    detail = _selected_detail(source)
    action = detail.get('action', {})
    descriptor = detail.get('descriptor', {})
    if not isinstance(action, dict) or not isinstance(descriptor, dict):
        return False
    if not (descriptor.get('kind') == 'cast' or action.get('type') in ('spell', 'quick')):
        return False
    spell = descriptor.get('spell', {})
    if not isinstance(spell, dict) or spell.get('id') != event.get('spell_id'):
        return False
    side = event.get('use_dark_side')
    if isinstance(side, bool) and spell.get('use_dark_side') is not side:
        return False
    return True


def _room_auto_cast_matches(source: dict, event: dict) -> bool:
    if event.get('cast_origin') != 'room_cast_next_ready' or source.get('request_type') != 'action_activation_step':
        return False
    room_id = event.get('origin_room_id')
    if not isinstance(room_id, str) or not room_id:
        return False
    detail = _selected_detail(source)
    descriptor = detail.get('descriptor', {})
    action = detail.get('action', {})
    if not isinstance(descriptor, dict) or not isinstance(action, dict):
        return False
    kind = action.get('type')
    if kind == 'explore':
        after = action.get('activate_room_after_movement') is True
        before = action.get('activate_room_before_movement') is True
        if not (before ^ after):
            return False
        if after and (descriptor.get('final_room_id') != room_id):
            return False
        return True
    if kind == 'fight':
        return action.get('perform_room_activation', True) is True
    return False



def _reaction_card_selection_step(transitions: list[dict], event: dict) -> int | None:
    """Prove an optional Trap/Protection was *chosen* by this player.

    A board-based trigger decision can take two agent decisions:
    (1) choose the armed Spell card, (2) confirm the selection.  The R3
    receipt currently records the confirmation step; that is not a Cast.
    Credit the first decision (which picked the card) only when both exact
    consecutive choices are present in the authoritative episode.

    This does not search arbitrary prior casts or infer a delayed effect.
    """
    if event.get('kind') != 'reaction' or event.get('spell_type') not in ('trap', 'protection'):
        return None
    confirmation = int(event['step'])
    owner = int(event['player_index'])
    if confirmation < 2 or confirmation > len(transitions):
        return None
    confirm_record = transitions[confirmation - 1]
    selection_record = transitions[confirmation - 2]
    if (int(confirm_record.get('step', -1)) != confirmation
            or int(selection_record.get('step', -1)) != confirmation - 1
            or int(confirm_record.get('player_index', -1)) != owner
            or int(selection_record.get('player_index', -1)) != owner
            or confirm_record.get('request_type') != 'effect_choice'
            or selection_record.get('request_type') != 'effect_choice'):
        return None
    confirm_options = confirm_record.get('legal_candidates')
    selection_options = selection_record.get('legal_candidates')
    if not isinstance(confirm_options, list) or not isinstance(selection_options, list):
        return None
    try:
        confirm_idx = int(confirm_record['selected_candidate_id'])
        select_idx = int(selection_record['selected_candidate_id'])
        if not (0 <= confirm_idx < len(confirm_options) and 0 <= select_idx < len(selection_options)):
            return None
        confirm = confirm_options[confirm_idx]
        selected = selection_options[select_idx]
        if not isinstance(confirm, dict) or not isinstance(selected, dict):
            return None
        c_detail, s_detail = confirm.get('detail'), selected.get('detail')
        c_payload, s_payload = confirm.get('payload'), selected.get('payload')
        if not all(isinstance(x, dict) for x in (c_detail, s_detail, c_payload, s_payload)):
            return None
        if (c_payload.get('ai_finish') is not True
                or str(confirm.get('label', '')).strip().lower() != 'confirm selection'
                or int(c_detail.get('selected_count', 0)) < 1):
            return None
        if (s_detail.get('card_kind') != 'spells'
                or str(s_detail.get('id', '')) != str(event['spell_id'])
                or int(s_detail.get('board_player_index', -1)) != owner
                or not str(s_payload.get('ai_select', '')).startswith('arm:')
                or not str(selected.get('label', '')).startswith('Select ')):
            return None
    except (KeyError, ValueError, TypeError, OverflowError):
        return None
    return confirmation - 1


def _reaction_single_step_selection_step(transitions: list[dict], event: dict) -> int | None:
    """Validate single-choice board reaction, as seen with Sarcophagus in game 399.

    The player's *actual* choice is one effect_choice with an armed Spell
    token, alongside an explicit 'Select none' alternative.  Unlike the
    two-phase board selector, there is no subsequent confirmation step.
    Require all available non-pass candidates to be armed Spell cards for
    the same owner.  This is deliberately fail-closed for other UI shapes.
    """
    if event.get('kind') != 'reaction' or event.get('spell_type') not in ('trap', 'protection'):
        return None
    try:
        step = int(event['step'])
        owner = int(event['player_index'])
        if not (1 <= step <= len(transitions)):
            return None
        record = transitions[step - 1]
        if (int(record.get('step', -1)) != step
                or int(record.get('player_index', -1)) != owner
                or record.get('request_type') != 'effect_choice'):
            return None
        options = record.get('legal_candidates')
        selected_index = int(record['selected_candidate_id'])
        if not isinstance(options, list) or not (1 < len(options) <= 50):
            return None
        if not (0 <= selected_index < len(options)):
            return None
        has_opt_out = False
        for candidate in options:
            if not isinstance(candidate, dict):
                return None
            label = str(candidate.get('label', ''))
            detail = candidate.get('detail')
            payload = candidate.get('payload')
            if not isinstance(detail, dict) or not isinstance(payload, dict):
                return None
            if label.strip().lower() == 'select none':
                if detail or has_opt_out:
                    return None
                has_opt_out = True
                continue
            token = str(detail.get('token', ''))
            if (detail.get('card_kind') != 'spells'
                    or int(detail.get('board_player_index', -1)) != owner
                    or not str(detail.get('id', ''))
                    or not str(detail.get('slot_id', ''))
                    or not token.startswith('arm:')
                    or label != token
                    or payload.get('selection') != token):
                return None
        if not has_opt_out:
            return None
        chosen = options[selected_index]
        d = chosen['detail']
        if (d.get('card_kind') != 'spells'
                or d.get('id') != event.get('spell_id')):
            return None
        return step
    except (KeyError, TypeError, ValueError, OverflowError):
        return None

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
    room_auto_casts = 0
    reaction_card_selections = 0
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
        if int(source.get('step', -1)) != step or int(source.get('player_index', -1)) != owner:
            raise ValueError(f'R3 event {ix}: step/owner attribution invalid at {step}')
        origin = event.get('cast_origin', 'direct')
        credited_step = step
        if origin == 'direct':
            if not _direct_cast_matches(source, event):
                # A selected Trap/Protection is not a new Cast.  In board UI,
                # choosing the armed card and confirming it are two AI steps.
                # The existing R3 Game marked the confirmation as a direct
                # cast; accept only a proven selection->confirmation pair.
                chosen_step = _reaction_card_selection_step(transitions, event)
                if chosen_step is None:
                    chosen_step = _reaction_single_step_selection_step(transitions, event)
                if chosen_step is None:
                    raise ValueError(f'R3 event {ix}: direct-cast spell identity mismatch at step {step}; no verified reaction selection')
                credited_step = chosen_step
                reaction_card_selections += 1
        elif origin == 'room_cast_next_ready':
            if not _room_auto_cast_matches(source, event):
                raise ValueError(f'R3 event {ix}: room-auto-cast provenance invalid at step {step}')
            room_auto_casts += 1
        else:
            raise ValueError(f'R3 event {ix}: unsupported cast origin {origin!r}')
        value = reward.REACTION_EFFECT_BONUS if kind == 'reaction' else reward.SPELL_EFFECT_BONUS
        per_step[credited_step] = per_step.get(credited_step, 0.0) + value
        counts[kind] += 1
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
        'room_auto_casts': room_auto_casts,
        'reaction_card_selections': reaction_card_selections,
    }
    return per_step, summary
