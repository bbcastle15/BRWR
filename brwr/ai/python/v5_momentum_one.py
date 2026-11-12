"""V5: one TOP-LEVEL Momentum choice, irrespective of discard/direction variants.

Only action_activation_step is changed. The policy is hierarchical:
  1) Cast: EACH legal cast is an independent top-level choice.
     Momentum: ALL legal Momentum variants together are ONE top-level choice.
     Other families (Explore/Fight/Quest/Finish/...): ONE top-level choice per
     family, preserving V5 group protection against thousands of explore paths.
  2) After a collapsed family wins, select an exact legal variant with a
     conditional softmax of the original neural logits.

For a collapsed family, the first-stage logit is the arithmetic MEAN of its
candidate logits. Therefore duplicating an identical Momentum variant does
not increase its total probability. All final actions remain legal and the
Python log-probabilities are differentiated during policy-gradient training.

The Godot sampler in ai_native_policy_v5_momentumone.gd implements the same
math. Do not substitute a flat softmax in the trainer.
"""
from __future__ import annotations

from collections import Counter
import math

import torch
from torch.nn import functional as F

VERSION = 'v5_momentum_one_cast_individual_v1'
ACTION_REQUEST = 'action_activation_step'
INDEPENDENT_FAMILIES = frozenset(('cast',))


def action_family(candidate: dict) -> str:
    if not isinstance(candidate, dict):
        raise ValueError('Candidate must be a dictionary')
    detail = candidate.get('detail', {})
    if not isinstance(detail, dict):
        raise ValueError('Candidate detail must be a dictionary')
    descriptor = detail.get('descriptor', {})
    if not isinstance(descriptor, dict):
        raise ValueError('Candidate descriptor must be a dictionary')
    family = descriptor.get('kind') or detail.get('kind')
    if not isinstance(family, str) or not family:
        raise ValueError('Action candidate lacks stable family discriminator')
    return family


def action_families(candidates: list, request_type: str) -> list[str]:
    if not isinstance(candidates, list) or not candidates:
        raise ValueError('Expected nonempty candidates list')
    if request_type != ACTION_REQUEST:
        return ['__unchanged__'] * len(candidates)
    return [action_family(c) for c in candidates]


def _structure(candidates: list):
    """Return slot membership, indexes of collapsed groups, and their order."""
    groups = {}
    for i, family in enumerate(action_families(candidates, ACTION_REQUEST)):
        groups.setdefault(family, []).append(i)
    slots = []  # (family, candidate index or None)
    for family, indexes in groups.items():
        if family in INDEPENDENT_FAMILIES:
            slots.extend((family, index) for index in indexes)
        else:
            slots.append((family, None))
    return groups, slots


def log_probabilities(logits: torch.Tensor, candidates: list,
                      request_type: str) -> torch.Tensor:
    if logits.ndim != 1 or logits.numel() != len(candidates) or not candidates:
        raise ValueError('Logit count and candidate count mismatch')
    if not torch.isfinite(logits).all():
        raise ValueError('Nonfinite logits')
    if request_type != ACTION_REQUEST:
        return F.log_softmax(logits, dim=0)

    groups, slots = _structure(candidates)
    slot_scores = torch.stack([
        logits[index] if index is not None else logits[groups[family]].mean()
        for family, index in slots
    ])
    slot_lp = F.log_softmax(slot_scores, dim=0)
    # Vectorized assignment keeps large Explore families efficient and preserves
    # autograd, unlike stacking one Python tensor per legal action.
    out = torch.empty_like(logits)
    for slot_id, (family, index) in enumerate(slots):
        if index is not None:
            out[index] = slot_lp[slot_id]
        else:
            ids = groups[family]
            out[ids] = slot_lp[slot_id] + F.log_softmax(logits[ids], dim=0)
    return out



def entropy(log_probs: torch.Tensor, candidates: list, request_type: str) -> torch.Tensor:
    """Entropy of virtual first-stage choices plus normalized conditional entropy.

    The entropy term should NOT incentivize Momentum simply because it has
    many possible directions/discards. At identical logits, its gradient is
    zero for any multiplicities, including two independent Cast actions.
    """
    if log_probs.ndim != 1 or log_probs.numel() != len(candidates) or not candidates:
        raise ValueError('Log-probability count and candidate count mismatch')
    if request_type != ACTION_REQUEST:
        probs = log_probs.exp()
        return -(probs * log_probs).sum()

    groups, slots = _structure(candidates)
    top_lp = torch.stack([
        log_probs[index] if index is not None else torch.logsumexp(log_probs[groups[family]], dim=0)
        for family, index in slots
    ])
    top_p = top_lp.exp()
    first_stage_entropy = -(top_p * top_lp).sum()

    within = []
    for family, indexes in groups.items():
        if family in INDEPENDENT_FAMILIES or len(indexes) <= 1:
            continue
        conditional_lp = F.log_softmax(log_probs[indexes], dim=0)
        within.append(-(conditional_lp.exp() * conditional_lp).sum() / math.log(len(indexes)))
    if not within:
        return first_stage_entropy
    return first_stage_entropy + torch.stack(within).mean()


def summaries(transitions: list[dict]) -> dict:
    """Read-only diagnostic; no reward or gradient changes."""
    selected, available, slots = Counter(), Counter(), Counter()
    decisions = 0
    with_cast_momentum = 0
    cast_picked_with_momentum = 0
    momentum_picked_with_cast = 0
    for row in transitions:
        if row.get('request_type') != ACTION_REQUEST:
            continue
        candidates = row['legal_candidates']
        families = action_families(candidates, ACTION_REQUEST)
        available.update(families)
        _, primary = _structure(candidates)
        slots.update(family for family, _ in primary)
        index = row['selected_candidate_id']
        if not isinstance(index, int) or not 0 <= index < len(families):
            raise ValueError('Selected candidate index invalid')
        family = families[index]
        selected[family] += 1
        decisions += 1
        if 'cast' in families and 'momentum' in families:
            with_cast_momentum += 1
            if family == 'cast':
                cast_picked_with_momentum += 1
            if family == 'momentum':
                momentum_picked_with_cast += 1
    return {'action_steps': decisions, 'selected': dict(selected),
            'candidate_totals': dict(available), 'virtual_slots': dict(slots),
            'steps_with_cast_and_momentum': with_cast_momentum,
            'cast_when_both': cast_picked_with_momentum,
            'momentum_when_both': momentum_picked_with_cast}


def audit_probabilities(model, experiences, transitions):
    """Use model weights from this episode BEFORE updating them; no gradient.

    Reports expected probability and observed choice at real action steps
    where Cast and Momentum coexist. Logs make sampling failures visible,
    rather than relying on only synthetic 21-vs-2 tests.
    """
    if len(experiences) != len(transitions):
        raise ValueError('Audit experiences/transitions length mismatch')
    both = 0
    momentum_total = 0.0
    cast_total = 0.0
    mom_selected = 0
    cast_selected = 0
    with torch.no_grad():
        for transition, row in zip(experiences, transitions):
            if row.get('request_type') != ACTION_REQUEST:
                continue
            families = action_families(row['legal_candidates'], ACTION_REQUEST)
            if 'momentum' not in families or 'cast' not in families:
                continue
            logits = model(transition.candidate_features)
            probs = log_probabilities(logits, row['legal_candidates'], ACTION_REQUEST).exp()
            if row.get('selected_candidate_id') != transition.selected:
                raise ValueError('Audit selected candidate mismatch')
            if not torch.isfinite(probs).all() or abs(probs.sum().item() - 1.0) > 1e-5:
                raise ValueError('Audit invalid probability normalization')
            momentum_total += float(probs[[i for i, f in enumerate(families) if f == 'momentum']].sum())
            cast_total += float(probs[[i for i, f in enumerate(families) if f == 'cast']].sum())
            chosen = families[transition.selected]
            mom_selected += int(chosen == 'momentum')
            cast_selected += int(chosen == 'cast')
            both += 1
    return {'steps_both': both, 'mean_momentum_probability': momentum_total / both if both else 0.,
            'mean_cast_probability': cast_total / both if both else 0.,
            'momentum_selected': mom_selected, 'cast_selected': cast_selected}
