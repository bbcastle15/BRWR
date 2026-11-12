"""Reward and *previous-episode* baseline for isolated BRWR v5-R3 experiment.

No Godot dependency, no file IO, no policy/model code.
Linear in the observed range of margins [-48,-26] to avoid tanh saturation.
Clipping at +/-80 BR points and +/-20 peer points is a safety bound, not a
claim about achievable scores. A win bonus remains dominant over a loss.  Requires public terminal
scoreboard only. The same-game mages are *not* used as a baseline for advantage.
They enter the reward with deliberately small relative weighting.
"""
from __future__ import annotations

import math
from typing import Any

REWARD_VERSION = 'v5_reward_points_rose_peer_v3'
BASELINE_VERSION = 'previous_episode_ema_shrinkage_v3'
WIN_REWARD = 2.0
LOSE_REWARD = -1.0
PERSONAL_POINT_WEIGHT = 0.030
ROSE_MARGIN_WEIGHT = 0.015
ROSE_MARGIN_CAP_POINTS = 80.0
PEER_WEIGHT = 0.002
SPELL_EFFECT_BONUS = 0.005
REACTION_EFFECT_BONUS = 0.007
PEER_CAP_POINTS = 20.0
EMA_ALPHA = 0.15
SHRINK_PSEUDO_COUNT = 3.0
ADVANTAGE_LIMIT = 1.0


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool):
        raise ValueError(f'{label}: booleans are not scores')
    try:
        out = float(value)
    except (ValueError, TypeError) as exc:
        raise ValueError(f'{label}: invalid score {value!r}') from exc
    if not math.isfinite(out):
        raise ValueError(f'{label}: nonfinite score')
    return out


def extract_scores(end: dict, bots: int) -> tuple[float, list[float], int]:
    if not isinstance(end, dict) or not isinstance(end.get('scores'), list):
        raise ValueError('episode_end lacks scores list')
    if bots < 2 or bots > 6:
        raise ValueError('Unsupported player count')
    scores: dict[int, float] = {}
    for item in end['scores']:
        if not isinstance(item, dict):
            raise ValueError('Invalid scoreboard entry')
        try:
            idx = int(item['player_index'])
        except (ValueError, TypeError, KeyError) as exc:
            raise ValueError('Invalid scoreboard player_index') from exc
        if idx in scores:
            raise ValueError(f'Duplicate player index {idx}')
        scores[idx] = _number(item.get('total'), f'player {idx} total')
    if -1 not in scores:
        raise ValueError('Black Rose/Avatar total missing (index -1): refusing fabricated score')
    missing = [i for i in range(bots) if i not in scores]
    if missing:
        raise ValueError('Missing mage scores: ' + repr(missing))
    try:
        winner = int(end['winner'])
    except (ValueError, TypeError, KeyError) as exc:
        raise ValueError('Invalid episode winner') from exc
    if winner not in [-1, *range(bots)]:
        raise ValueError(f'Unknown winner {winner}')
    return scores[-1], [scores[i] for i in range(bots)], winner


def rose_peer_rewards(end: dict, bots: int) -> tuple[list[float], dict]:
    rose_score, mage_scores, winner = extract_scores(end, bots)
    rewards = []
    rows = []
    for i, own in enumerate(mage_scores):
        other_mean = (sum(mage_scores) - own) / (bots - 1)
        outcome = WIN_REWARD if winner == i else LOSE_REWARD
        rose = ROSE_MARGIN_WEIGHT * max(-ROSE_MARGIN_CAP_POINTS, min(ROSE_MARGIN_CAP_POINTS, own - rose_score))
        peer = PEER_WEIGHT * max(-PEER_CAP_POINTS, min(PEER_CAP_POINTS, own - other_mean))
        own_points = PERSONAL_POINT_WEIGHT * own
        rewards.append(outcome + own_points + rose + peer)
        rows.append({'mage': i, 'own_score': own, 'rose_margin': own - rose_score,
                     'peer_margin': own - other_mean, 'outcome': outcome,
                     'personal_points_reward': own_points,
                     'rose_reward': rose, 'peer_reward': peer})
    info = {'rose_score': rose_score, 'mage_scores': mage_scores,
            'best_mage_score': max(mage_scores), 'mean_mage_score': sum(mage_scores) / bots,
            'best_margin_vs_rose': max(mage_scores) - rose_score,
            'winner': winner, 'components': rows}
    return rewards, info


def new_baseline_state() -> dict:
    return {'version': BASELINE_VERSION, 'global': {'n': 0, 'mean': 0.0}, 'scenarios': {}}


def validate_baseline_state(state: dict) -> None:
    if not isinstance(state, dict) or state.get('version') != BASELINE_VERSION:
        raise ValueError('Baseline state/version missing or incompatible')
    if not isinstance(state.get('scenarios'), dict):
        raise ValueError('Baseline scenarios missing')
    for record in [state.get('global'), *state['scenarios'].values()]:
        if not isinstance(record, dict) or not isinstance(record.get('n'), int) or record['n'] < 0:
            raise ValueError('Invalid baseline count')
        _number(record.get('mean'), 'baseline mean')


def scenario_key(bots: int, avatar: str, difficulty: str) -> str:
    return f'h{bots}_av{avatar}_{difficulty}'


def predict_baseline(state: dict, key: str) -> tuple[float | None, str]:
    """Returns a baseline computed only from completed *previous* episodes.

    If no prior episode exists, return None: first episode is calibration-only.
    Shrink scenario-specific EMA toward global EMA when examples are scarce.
    """
    validate_baseline_state(state)
    global_stats = state['global']
    if global_stats['n'] == 0:
        return None, 'initial_calibration'
    scenario = state['scenarios'].get(key)
    if not scenario or scenario['n'] == 0:
        return float(global_stats['mean']), 'global_history'
    weight = scenario['n'] / (scenario['n'] + SHRINK_PSEUDO_COUNT)
    blended = weight * scenario['mean'] + (1.0 - weight) * global_stats['mean']
    return float(blended), 'scenario_global_blend'


def _ema_update(record: dict, sample: float) -> None:
    if record['n'] == 0:
        record['mean'] = sample
    else:
        record['mean'] += EMA_ALPHA * (sample - record['mean'])
    record['n'] += 1


def observe_completed_episode(state: dict, key: str, rewards: list[float]) -> None:
    """Call strictly AFTER policy gradient has been computed (if applicable)."""
    validate_baseline_state(state)
    if not rewards:
        raise ValueError('Cannot update baseline from an empty game')
    sample = sum(_number(r, 'reward') for r in rewards) / len(rewards)
    stats = state['scenarios'].setdefault(key, {'n': 0, 'mean': 0.0})
    _ema_update(stats, sample)
    _ema_update(state['global'], sample)


def compute_advantages(rewards: list[float], historical_baseline: float | None) -> tuple[list[float], list[float], int]:
    if historical_baseline is None:
        return [], [], 0
    baseline = _number(historical_baseline, 'historical baseline')
    raw = [_number(r, 'reward') - baseline for r in rewards]
    clipped = [max(-ADVANTAGE_LIMIT, min(ADVANTAGE_LIMIT, x)) for x in raw]
    count = sum(a != b for a, b in zip(raw, clipped))
    return clipped, raw, count
