"""Deterministic probability, gradient, and learnability tests; no Godot needed."""
import math
import unittest

import torch
from torch.nn import functional as F
import v5_momentum_one as g


def option(i, family, direction=None, discard=None):
    if family == 'finish':
        return {'id': i, 'detail': {'kind': 'finish', 'descriptor': {}, 'action': {}}}
    action = {'type': family}
    if direction is not None:
        action['direction'] = direction
    if discard is not None:
        action['discard'] = discard
    return {'id': i, 'detail': {'kind': 'action', 'descriptor': {'kind': family}, 'action': action}}


class MomentumOneTests(unittest.TestCase):
    def test_21_momentum_two_cast_one_third_vs_two_thirds(self):
        items = [option(i, 'momentum', direction=i % 3, discard=i // 3) for i in range(21)]
        items += [option(21, 'cast'), option(22, 'cast')]
        lp = g.log_probabilities(torch.zeros(23), items, g.ACTION_REQUEST)
        p = lp.exp()
        self.assertAlmostEqual(float(p[:21].sum()), 1 / 3, places=6)
        self.assertAlmostEqual(float(p[21:].sum()), 2 / 3, places=6)
        self.assertAlmostEqual(float(p[0]), 1 / 63, places=6)
        self.assertAlmostEqual(float(p[21]), 1 / 3, places=6)

    def test_duplication_of_momentum_variants_does_not_raise_mass(self):
        outcomes = []
        for count in (1, 3, 21, 101, 700):
            cs = [option(i, 'momentum', direction=i % 4, discard=i // 4) for i in range(count)]
            cs.extend([option(count, 'cast'), option(count+1, 'cast')])
            p = g.log_probabilities(torch.zeros(len(cs)), cs, g.ACTION_REQUEST).exp()
            outcomes.append(float(p[:count].sum()))
        self.assertTrue(all(abs(x - 1/3) < 2e-6 for x in outcomes), outcomes)

    def test_other_families_do_not_dominate_by_path_count(self):
        kinds = ['explore'] * 300 + ['momentum'] * 21 + ['fight'] * 7 + ['cast'] * 2 + ['finish']
        cs = [option(i, family) for i, family in enumerate(kinds)]
        p = g.log_probabilities(torch.zeros(len(cs)), cs, g.ACTION_REQUEST).exp()
        self.assertAlmostEqual(float(p[:300].sum()), 1/6, places=6)
        self.assertAlmostEqual(float(p[300:321].sum()), 1/6, places=6)
        self.assertAlmostEqual(float(p[321:328].sum()), 1/6, places=6)
        self.assertAlmostEqual(float(p[328:330].sum()), 2/6, places=6)
        self.assertAlmostEqual(float(p[330]), 1/6, places=6)

    def test_families_with_varied_logits_use_mean_not_max_or_count(self):
        cs = [option(i, 'momentum') for i in range(3)] + [option(3,'cast'), option(4,'cast')]
        scores = torch.tensor([1.0, 0.0, -1.0, 0.0, 0.0])
        p = g.log_probabilities(scores, cs, g.ACTION_REQUEST).exp()
        self.assertAlmostEqual(float(p[:3].sum()), 1/3, places=6)
        self.assertAlmostEqual(float(p[0]/p[2]), math.exp(2), places=5)

    def test_non_action_choices_unchanged(self):
        cs = [option(i,'momentum') for i in range(21)] + [option(21,'cast')]
        scores = torch.arange(22, dtype=torch.float32) / 8
        for request in ('preparation', 'effect_choice', 'discard_choice'):
            self.assertTrue(torch.allclose(g.log_probabilities(scores, cs, request), F.log_softmax(scores, dim=0)))

    def test_missing_family_rejected_only_on_action(self):
        cs = [{'id': 0, 'detail': {}}]
        with self.assertRaisesRegex(ValueError, 'family'):
            g.log_probabilities(torch.zeros(1), cs, g.ACTION_REQUEST)
        self.assertEqual(g.log_probabilities(torch.zeros(1), cs, 'other').numel(), 1)

    def test_finish_fallback(self):
        self.assertEqual(g.action_family(option(0, 'finish')), 'finish')

    def test_negative_momentum_advantage_reduces_momentum_probability(self):
        cs = [option(i, 'momentum') for i in range(21)] + [option(21, 'cast'), option(22, 'cast')]
        scores = torch.nn.Parameter(torch.zeros(23))
        optim = torch.optim.SGD([scores], lr=10.0)
        before = float(g.log_probabilities(scores, cs, g.ACTION_REQUEST).exp()[:21].sum().detach())
        loss = -(-0.003) * g.log_probabilities(scores, cs, g.ACTION_REQUEST)[0]
        optim.zero_grad(); loss.backward(); optim.step()
        after = float(g.log_probabilities(scores, cs, g.ACTION_REQUEST).exp()[:21].sum().detach())
        self.assertLess(after, before)

    def test_learn_cast_even_with_hundreds_of_momentum_variants(self):
        cs = [option(i, 'momentum') for i in range(250)] + [option(250, 'cast')]
        scores = torch.nn.Parameter(torch.zeros(len(cs)))
        optim = torch.optim.Adam([scores], lr=0.075)
        for _ in range(65):
            lp = g.log_probabilities(scores, cs, g.ACTION_REQUEST)
            loss = -lp[-1] - 0.02 * g.entropy(lp, cs, g.ACTION_REQUEST)
            optim.zero_grad(); loss.backward(); optim.step()
        with torch.no_grad():
            p = g.log_probabilities(scores, cs, g.ACTION_REQUEST).exp()
            self.assertGreater(float(p[-1]), 0.9)

    def test_entropy_is_stationary_for_uniform_virtual_slots(self):
        cs = [option(i,'momentum') for i in range(21)] + [option(21,'cast'), option(22,'cast')]
        scores = torch.nn.Parameter(torch.zeros(len(cs)))
        lp = g.log_probabilities(scores, cs, g.ACTION_REQUEST)
        h = g.entropy(lp, cs, g.ACTION_REQUEST)
        self.assertAlmostEqual(float(h.detach()), math.log(3) + 1.0, places=6)
        (-h).backward()
        self.assertLess(float(scores.grad.abs().max()), 1e-5)

    def test_real_logit_vector_probability_normalization_and_grad(self):
        cs = [option(i, f) for i, f in enumerate(['momentum']*21 + ['explore']*17 + ['cast']*3 + ['fight']*2)]
        scores = torch.nn.Parameter(torch.linspace(-2, 2, len(cs)))
        lp = g.log_probabilities(scores, cs, g.ACTION_REQUEST)
        self.assertAlmostEqual(float(lp.exp().sum().detach()), 1.0, places=5)
        loss = -lp[40] - 0.01*g.entropy(lp, cs, g.ACTION_REQUEST)
        loss.backward()
        self.assertTrue(torch.isfinite(scores.grad).all())

    def test_real_probability_audit_with_both_categories(self):
        class DummyModel(torch.nn.Module):
            def forward(self, features):
                return features
        class Experience:
            def __init__(self, logits, selected):
                self.candidate_features = logits
                self.selected = selected
        cs = [option(i, 'momentum') for i in range(21)] + [option(21, 'cast'), option(22, 'cast')]
        exp = [Experience(torch.zeros(23), 22), Experience(torch.zeros(23), 0)]
        rows = [{'request_type': g.ACTION_REQUEST, 'legal_candidates': cs,
                 'selected_candidate_id': x.selected} for x in exp]
        audit = g.audit_probabilities(DummyModel(), exp, rows)
        self.assertEqual(audit['steps_both'], 2)
        self.assertAlmostEqual(audit['mean_momentum_probability'], 1/3, places=6)
        self.assertAlmostEqual(audit['mean_cast_probability'], 2/3, places=6)
        self.assertEqual(audit['cast_selected'], 1)
        self.assertEqual(audit['momentum_selected'], 1)

    def test_log_stats_count_virtual_slots_correctly(self):
        cs = [option(i,'momentum') for i in range(21)] + [option(21,'cast'), option(22,'cast')]
        data = [{'request_type':g.ACTION_REQUEST,'legal_candidates':cs,'selected_candidate_id':0}]
        stats = g.summaries(data)
        self.assertEqual(stats['virtual_slots'], {'momentum':1, 'cast':2})
        self.assertEqual(stats['candidate_totals'], {'momentum':21, 'cast':2})
        self.assertEqual(stats['momentum_when_both'], 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
