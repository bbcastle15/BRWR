"""Candidate-count-neutral categorical policy for BRWR v5.

Action activation chooses a family (cast/momentum/explore/...) without
multiplicity bias, then a concrete option inside that family. Mathematically
P(a) = exp(s_a) / N_family(a) / sum_b(exp(s_b)/N_family(b)).
All other request types retain the original softmax exactly.
Both Godot and the PyTorch trainer MUST use the same adjustment.
"""
from __future__ import annotations
from collections import Counter
import math
import torch
from torch.nn import functional as F

VERSION = 'v5_action_family_balanced_logcount_v1'
ACTION_REQUEST = 'action_activation_step'


def action_family(candidate: dict) -> str:
    if not isinstance(candidate, dict):
        raise ValueError('Candidate must be a dictionary')
    detail = candidate.get('detail', {})
    if not isinstance(detail, dict):
        raise ValueError('Candidate detail must be a dictionary')
    descriptor = detail.get('descriptor', {})
    if not isinstance(descriptor, dict):
        raise ValueError('Candidate descriptor must be a dictionary')
    # 'finish' has detail.kind='finish' and an empty descriptor.
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


def log_probabilities(logits: torch.Tensor, candidates: list, request_type: str) -> torch.Tensor:
    if logits.ndim != 1 or logits.numel() != len(candidates):
        raise ValueError('Logit count and candidate count mismatch')
    if request_type != ACTION_REQUEST:
        return F.log_softmax(logits, dim=0)
    families = action_families(candidates, request_type)
    counts = Counter(families)
    correction = logits.new_tensor([-math.log(counts[g]) for g in families])
    return F.log_softmax(logits + correction, dim=0)


def entropy(log_probs: torch.Tensor, candidates: list, request_type: str) -> torch.Tensor:
    """Entropy of families plus normalized mean within-family entropy.

    Original full-candidate entropy is biased towards families with many
    candidates even after the log-count correction. Normalizing each
    within-family entropy by log(N) removes this incentive. The policy still
    explores all the separate paths/spells inside each family.
    """
    if log_probs.ndim != 1 or log_probs.numel() != len(candidates):
        raise ValueError('Log-probability count and candidate count mismatch')
    if request_type != ACTION_REQUEST:
        probs = log_probs.exp()
        return -(probs * log_probs).sum()
    families = action_families(candidates, request_type)
    group_indices = {}
    for index, family in enumerate(families):
        group_indices.setdefault(family, []).append(index)
    group_log_p = torch.stack([torch.logsumexp(log_probs[idx], dim=0)
                               for idx in group_indices.values()])
    group_p = group_log_p.exp()
    group_h = -(group_p * group_log_p).sum()
    within = []
    for group, indices in group_indices.items():
        if len(indices) == 1:
            within.append(log_probs.new_zeros(()))
            continue
        cond_log_p = F.log_softmax(log_probs[indices], dim=0)
        cond_p = cond_log_p.exp()
        within.append(-(cond_p * cond_log_p).sum() / math.log(len(indices)))
    return group_h + torch.stack(within).mean()


def summaries(transitions: list[dict]) -> dict:
    """Read-only diagnostic; no reward or gradient changes."""
    choices, counts = Counter(), Counter()
    decisions = 0
    for row in transitions:
        if row.get('request_type') != ACTION_REQUEST:
            continue
        candidates = row['legal_candidates']
        names = action_families(candidates, ACTION_REQUEST)
        decisions += 1
        counts.update(names)
        selected = row['selected_candidate_id']
        if not isinstance(selected, int) or not 0 <= selected < len(names):
            raise ValueError('Selected candidate index invalid')
        choices[names[selected]] += 1
    return {'action_steps': decisions, 'selected': dict(choices), 'candidate_totals': dict(counts)}
