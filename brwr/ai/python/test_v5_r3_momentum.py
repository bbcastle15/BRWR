"""No-Godot tests for the isolated local Momentum policy-gradient penalty."""
import copy
import unittest
import v5_r3_momentum as m
import v5_reward_v3 as reward


def candidate(cid, kind, typ=None, label=None):
    return {'id': cid, 'label': label if label is not None else kind,
            'detail': {'descriptor': {'kind': kind}, 'action': {'type': typ or kind}}}


def row(step, chosen, legal, request='action_activation_step', player=0):
    return {'record_type': 'transition', 'step': step, 'player_index': player,
            'request_type': request, 'selected_candidate_id': chosen, 'legal_candidates': legal}


class TestMomentumPenalty(unittest.TestCase):
    def test_momentum_selected_even_when_cast_exists(self):
        transitions = [row(1, 7, [candidate(1, 'cast', 'spell'), candidate(7,'momentum')])]
        penalties,stats = m.selected_momentum_penalties(transitions, 3)
        self.assertEqual(penalties, {1:-0.003})
        self.assertEqual(stats['momentum_actions'], 1)
        self.assertEqual(stats['with_cast_alternative'], 1)
        self.assertAlmostEqual(stats['total_penalty'], -0.003)

    def test_momentum_selected_when_only_momentum_exists(self):
        transitions = [row(1, 0, [candidate(0, 'momentum')])]
        penalties,stats = m.selected_momentum_penalties(transitions, 2)
        self.assertEqual(penalties, {1:-0.003})
        self.assertEqual(stats['with_cast_alternative'], 0)

    def test_no_penalty_for_cast_or_explore(self):
        transitions = [row(1, 2, [candidate(1, 'momentum'), candidate(2,'cast','spell')]),
                       row(2, 0, [candidate(0, 'explore')])]
        self.assertEqual(m.selected_momentum_penalties(transitions,2)[0], {})

    def test_no_penalty_for_preparation_discard_or_effect_choice(self):
        transitions = [row(1, 0, [candidate(0, 'momentum')], request='study_optional_discard'),
                       row(2, 0, [candidate(0, 'momentum')], request='effect_choice')]
        self.assertEqual(m.selected_momentum_penalties(transitions,2)[0], {})

    def test_label_is_not_enough(self):
        transitions = [row(1, 0, [candidate(0,'explore',label='Momentum: discard card')])]
        self.assertEqual(m.selected_momentum_penalties(transitions,2)[0], {})

    def test_mismatched_action_kind_rejected(self):
        transitions = [row(1, 0, [candidate(0,'momentum','explore')])]
        with self.assertRaisesRegex(ValueError,'Conflicting'):
            m.selected_momentum_penalties(transitions,2)

    def test_reject_missing_or_nonconsecutive_steps(self):
        with self.assertRaises(ValueError):
            m.selected_momentum_penalties([row(3,0,[candidate(0,'momentum')])],2)
        with self.assertRaises(ValueError):
            m.selected_momentum_penalties([row(1,9,[candidate(0,'momentum')])],2)

    def test_local_momentum_is_smaller_than_spell_and_point_reward(self):
        self.assertLess(abs(m.PENALTY), reward.SPELL_EFFECT_BONUS)
        self.assertLess(abs(m.PENALTY), reward.PERSONAL_POINT_WEIGHT)
        self.assertLess(abs(m.PENALTY), reward.ROSE_MARGIN_WEIGHT)

    def test_exact_selected_step_only_and_multi_player(self):
        transitions=[row(1,0,[candidate(0,'explore')],player=0),
                     row(2,7,[candidate(7,'momentum')],player=1),
                     row(3,0,[candidate(0,'cast','quick')],player=2),
                     row(4,1,[candidate(1,'momentum')],player=2)]
        penalties,stats=m.selected_momentum_penalties(transitions,3)
        self.assertEqual(penalties,{2:-0.003,4:-0.003})
        self.assertEqual(stats['action_decisions'],4)
        self.assertEqual(stats['momentum_actions'],2)


if __name__=='__main__': unittest.main(verbosity=2)
