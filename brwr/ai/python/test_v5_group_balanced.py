"""Fast deterministic unit, gradient and learnability tests; no simulation needed."""
import json
import math
import unittest
import torch
from torch.nn import functional as F
import v5_group_balanced as g


def option(i, kind):
    if kind == 'finish':
        return {'id': i, 'detail': {'kind':'finish','descriptor':{},'action':{}}}
    return {'id': i, 'detail': {'kind':'action','descriptor':{'kind':kind},'action':{'type':kind}}}


class BalancedTests(unittest.TestCase):
    def test_21_momentum_2_cast_50_50(self):
        items = [option(i,'momentum') for i in range(21)] + [option(i+21,'cast') for i in range(2)]
        lp = g.log_probabilities(torch.zeros(23), items, 'action_activation_step')
        self.assertAlmostEqual(float(lp.exp()[:21].sum()),0.5,places=6)
        self.assertAlmostEqual(float(lp.exp()[21:].sum()),0.5,places=6)

    def test_very_unequal_families_unchanged_when_all_scores_equal(self):
        items = [option(i,'explore') for i in range(50)] + [option(50,'finish'),option(51,'cast')]
        probs = g.log_probabilities(torch.zeros(52),items,'action_activation_step').exp()
        self.assertAlmostEqual(float(probs[:50].sum()),1/3,places=6)
        self.assertAlmostEqual(float(probs[50]),1/3,places=6)
        self.assertAlmostEqual(float(probs[51]),1/3,places=6)

    def test_non_action_choices_unchanged(self):
        items = [option(i,'momentum') for i in range(21)] + [option(21,'cast')]
        scores = torch.arange(22,dtype=torch.float32)/8
        actual = g.log_probabilities(scores,items,'preparation')
        self.assertTrue(torch.allclose(actual,F.log_softmax(scores,dim=0)))

    def test_missing_category_rejected_only_in_actions(self):
        items = [{'id': 0,'detail': {}}]
        with self.assertRaisesRegex(ValueError,'family'):
            g.log_probabilities(torch.zeros(1),items,'action_activation_step')
        self.assertEqual(g.log_probabilities(torch.zeros(1),items,'effect_choice').shape,(1,))

    def test_finish_fallback(self):
        self.assertEqual(g.action_family(option(0,'finish')),'finish')

    def test_negative_local_advantage_reduces_momentum_mass(self):
        items = [option(i,'momentum') for i in range(21)] + [option(21,'cast')]
        scores = torch.nn.Parameter(torch.zeros(22))
        opt = torch.optim.SGD([scores],lr=1.0)
        before = g.log_probabilities(scores,items,'action_activation_step').exp()[:21].sum().item()
        loss = -(torch.tensor(-0.003) * g.log_probabilities(scores,items,'action_activation_step')[0])
        opt.zero_grad(); loss.backward(); opt.step()
        after = g.log_probabilities(scores,items,'action_activation_step').exp()[:21].sum().item()
        self.assertLess(after,before)

    def test_learn_cast_with_large_momentum_multiplicity(self):
        items = [option(i,'momentum') for i in range(21)] + [option(21,'cast')]
        scores = torch.nn.Parameter(torch.zeros(22))
        opt = torch.optim.Adam([scores],lr=0.075)
        for _ in range(80):
            lp = g.log_probabilities(scores,items,'action_activation_step')
            loss = -lp[21] - 0.02*g.entropy(lp,items,'action_activation_step')
            opt.zero_grad();loss.backward();opt.step()
        prob = float(g.log_probabilities(scores,items,'action_activation_step').exp()[21].detach())
        self.assertGreater(prob,0.9)

    def test_entropy_not_biased_to_large_group_at_equal_logits(self):
        items = [option(i,'momentum') for i in range(21)] + [option(21,'cast')]
        scores=torch.nn.Parameter(torch.zeros(len(items)))
        lp = g.log_probabilities(scores,items,'action_activation_step')
        h = g.entropy(lp,items,'action_activation_step')
        self.assertAlmostEqual(float(h.detach()),math.log(2)+0.5,places=6)
        (-h).backward()
        # At uniform probabilities within each family the category entropy
        # is stationary, and normalised within-category entropy is too.
        self.assertLess(float(scores.grad.abs().max()),1e-5)

    def test_real_episode_many_categories(self):
        from pathlib import Path
        episode = Path(__file__).parent/'v5_real_decision_samples.jsonl'
        if not episode.exists():
            self.skipTest('Optional real episode fixture not installed')
        count=0
        with episode.open(encoding='utf-8') as f:
            for line in f:
                row=json.loads(line)
                if row.get('record_type') != 'transition' or row.get('request_type')!='action_activation_step':
                    continue
                cs = row['legal_candidates']
                lp = g.log_probabilities(torch.zeros(len(cs)),cs,'action_activation_step')
                self.assertAlmostEqual(float(lp.exp().sum()),1.,places=5)
                count += 1
        self.assertGreaterEqual(count,1)

if __name__=='__main__': unittest.main(verbosity=2)
