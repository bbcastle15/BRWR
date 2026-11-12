"""BRWR v5 candidate semantics experiment (not a training entry point).

The first 128 coordinates preserve v4 exactly. 256 additional coordinates
encode stable, owner-visible, candidate-specific semantic content. No game rules,
player secrets or outcome knowledge are introduced.

IMPORTANT: v5 is a different input representation. Use a separate checkpoint.
"""
from __future__ import annotations

import hashlib
import math
import re
from typing import Any

import train as v4

V4_DIM = v4.FEATURE_DIM
SEMANTIC_DIM = 256
FEATURE_DIM = V4_DIM + SEMANTIC_DIM
ENCODER_VERSION = 'brwr-v5-semantic-1'

_VOLATILE_KEYS = frozenset({
    'instance', 'instance_id', 'object_id', 'revision', 'signature', 'timestamp',
    'feedback_serial', 'global_position', 'screen_position', 'position',
    'x', 'y', 'id_hash', 'request_key',
})
_IGNORE_TEXT_KEYS = frozenset({'label', 'name', 'spell_name', 'personal_spell_name', 'grimoire_name'})
# Index and list length are not attributes of the card; map indices to owner-visible
# card IDs instead whenever possible.
_INDICES = frozenset({'ready_hand_indices', 'quick_hand_index', 'keep_indices', 'hand_index',
                      'hand_indices', 'draw_index', 'return_to_hand_indices', 'active_index',
                      'quest_index', 'quest_indices', 'queue_index', 'evocation_index'})
_NUMERICS = frozenset({'health', 'speed', 'strength', 'hand_limit', 'power', 'progress',
                       'cube_slots', 'count', 'damage', 'distance', 'max_select',
                       'min_select', 'ai_count', 'ready_count'})
# Never hash process-specific runtime object IDs, even in nested tokens.
_RUNTIME_ID = re.compile(r'^-?\d{8,}$')


def _canonical_text(value: str) -> str:
    value = value.strip().lower()
    if ':' not in value:
        return value
    prefix, suffix = value.split(':', 1)
    # Numeric IDs (not room names or typed string IDs) are process-dependent.
    if _RUNTIME_ID.fullmatch(suffix) or (prefix in {'hand', 'action'} and suffix.lstrip('-').isdigit()):
        return prefix + ':<runtime-id>'
    return value


def _fingerprint(value: str) -> int:
    digest = hashlib.blake2b(value.encode('utf-8'), digest_size=8).digest()
    return int.from_bytes(digest, 'big') % SEMANTIC_DIM


def _leaf_tokens(value: Any, path: str, key: str, terms: list[str], depth: int) -> None:
    if depth > 7 or key in _VOLATILE_KEYS:
        return
    if isinstance(value, dict):
        for subkey in sorted(value):
            if not isinstance(subkey, str):
                continue
            _leaf_tokens(value[subkey], f'{path}.{subkey}', subkey, terms, depth + 1)
    elif isinstance(value, list):
        terms.append(path + '.len=' + str(min(64, len(value))))
        for ix, item in enumerate(value[:64]):
            if isinstance(item, (dict, list)):
                _leaf_tokens(item, f'{path}[{ix}]', key, terms, depth + 1)
            else:
                _leaf_tokens(item, path + '[]', key, terms, depth + 1)
                # Position matters for ordered spells/path/dark sides.
                _leaf_tokens(item, f'{path}[{ix}]', key, terms, depth + 1)
    elif isinstance(value, bool):
        terms.append(path + '=' + ('true' if value else 'false'))
    elif isinstance(value, str):
        if key in _IGNORE_TEXT_KEYS:
            return
        value = _canonical_text(value)
        if value and len(value) <= 128:
            terms.append(path + '=' + value)
    elif isinstance(value, (int, float)):
        if key in _INDICES:
            return
        if key in _NUMERICS and math.isfinite(value) and abs(value) < 100000:
            terms.append(path + '=' + str(int(round(value))))


def _list_cards(observation: dict, decision: dict, key: str) -> list[dict]:
    pending = observation.get('pending_input', {})
    if not isinstance(pending, dict):
        pending = {}
    players = observation.get('players', [])
    player = int(decision.get('player_index', -1))
    own = players[player] if 0 <= player < len(players) and isinstance(players[player], dict) else {}
    if key == 'keep_indices' or key == 'draw_index':
        return pending.get('cards', []) if isinstance(pending.get('cards'), list) else []
    if key == 'return_to_hand_indices' or key == 'active_index':
        return pending.get('active_spells', own.get('active_spells', []))
    if key in {'quest_index', 'quest_indices'}:
        return pending.get('quests', own.get('active_quests', []))
    return pending.get('hand', own.get('hand', []))


def _referenced_cards(observation: dict, decision: dict, option: dict) -> list[str]:
    """Resolve indices against private player-visible observation, never raw IDs."""
    payload = option.get('payload', {})
    if not isinstance(payload, dict):
        return []
    out: list[str] = []
    for key in sorted(_INDICES):
        if key not in payload:
            continue
        raw = payload[key]
        indices = raw if isinstance(raw, list) else [raw]
        cards = _list_cards(observation, decision, key)
        if not isinstance(cards, list):
            continue
        for idx in indices:
            if isinstance(idx, bool) or not isinstance(idx, (float, int)) or int(idx) != idx or idx < 0:
                continue
            # Some staged options contain 'draw_index', 'hand_index' etc.
            match = None
            lookup_field = ('draw_index' if key in ('keep_indices', 'draw_index') else
                            'active_index' if key in ('return_to_hand_indices', 'active_index') else
                            'quest_index' if key in ('quest_index', 'quest_indices') else
                            'hand_index')
            for pos, card in enumerate(cards):
                if not isinstance(card, dict):
                    continue
                raw_position = card.get(lookup_field, pos)
                if isinstance(raw_position, (int, float)) and not isinstance(raw_position, bool) and raw_position == idx:
                    match = card
                    break
            if match is None and int(idx) < len(cards):
                match = cards[int(idx)]
            if isinstance(match, dict):
                identifier = match.get('id', match.get('spell_id', match.get('school_id', '')))
                if isinstance(identifier, str) and identifier:
                    out.append(f'resolved.{key}=' + _canonical_text(identifier))
    return out


def semantic_terms(observation: dict, decision: dict, option: dict) -> list[str]:
    detail = option.get('detail', {})
    payload = option.get('payload', {})
    terms: list[str] = []
    _leaf_tokens(detail, 'detail', 'detail', terms, 0)
    _leaf_tokens(payload, 'payload', 'payload', terms, 0)
    terms.extend(_referenced_cards(observation, decision, option))
    return terms


def semantic_features(observation: dict, decision: dict, option: dict) -> list[float]:
    features = [0.0] * SEMANTIC_DIM
    terms = semantic_terms(observation, decision, option)
    scale = 1.0 / math.sqrt(max(1, len(terms)))
    for term in terms:
        features[_fingerprint(term)] += scale
    return features


def encode_action(observation: dict, decision: dict, option: dict, index: int, total: int) -> list[float]:
    return v4.encode_action(observation, decision, option, index, total) + semantic_features(observation, decision, option)
