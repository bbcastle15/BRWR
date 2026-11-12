"""Tests for the R2 linear reward, scoreboard validation, baseline, and boundaries."""
import copy
import math
import unittest
import v5_reward_v2 as r


def end(rose, mage, winner=-1):
    return {'winner': winner, 'scores': [
        {'player_index': -1, 'total': rose},
        *[{'player_index': i, 'total': score} for i, score in enumerate(mage)]
    ]}


class RewardV2Tests(unittest.TestCase):
    def test_observed_margins_are_linear(self):
        a, _ = r.rose_peer_rewards(end(40, [2, 2, 2]), 3)
        b, _ = r.rose_peer_rewards(end(30, [2, 2, 2]), 3)
        self.assertAlmostEqual(b[0] - a[0], .15, places=10)

    def test_rose_priority_peer_is_secondary(self):
        # Compare ONE mage at constant BR margin, changing the other mages.
        equal, _ = r.rose_peer_rewards(end(40, [10, 10, 10]), 3)
        peers_down, _ = r.rose_peer_rewards(end(40, [10, 8, 8]), 3)
        self.assertAlmostEqual(peers_down[0] - equal[0], .006, places=9)
        better_rose, _ = r.rose_peer_rewards(end(30, [10, 10, 10]), 3)
        self.assertAlmostEqual(better_rose[0] - equal[0], .15, places=9)
        self.assertGreater(better_rose[0] - equal[0], 20 * (peers_down[0] - equal[0]))

    def test_win_bonus_dominates_even_at_clip(self):
        # Extremal losing outcome must still be worse than extremal winning.
        lose, _ = r.rose_peer_rewards(end(0, [1000, -1000], winner=-1), 2)
        win, _ = r.rose_peer_rewards(end(1000, [-1000, 1000], winner=0), 2)
        self.assertGreater(win[0], lose[0])

    def test_clips_outliers(self):
        extreme, _ = r.rose_peer_rewards(end(1000, [-1000, 0]), 2)
        at_cap, _ = r.rose_peer_rewards(end(80, [0, 0]), 2)
        self.assertLessEqual(abs(extreme[0]), 3)
        self.assertAlmostEqual(extreme[0], at_cap[0] - .06, places=8)

    def test_error_missing_rose_and_nan(self):
        bad = end(30, [1, 2]); bad['scores'] = bad['scores'][1:]
        with self.assertRaises(ValueError):
            r.rose_peer_rewards(bad, 2)
        with self.assertRaises(ValueError):
            r.rose_peer_rewards(end(30, [math.nan, 2]), 2)

    def test_same_game_not_used_for_baseline(self):
        st = r.new_baseline_state(); key = r.scenario_key(3, 'none', 'apprentice')
        self.assertIsNone(r.predict_baseline(st, key)[0])
        r.observe_completed_episode(st, key, [-1.5, -1.4, -1.6])
        frozen = copy.deepcopy(st)
        baseline, _ = r.predict_baseline(st, key)
        a, raw, clipped = r.compute_advantages([-1.35, -1.55], baseline)
        self.assertEqual(st, frozen)
        self.assertGreater(a[0], 0)
        self.assertLess(a[1], 0)
        # Unlike same-game centering, the advantage sum is not forced to zero.
        self.assertAlmostEqual(sum(raw), .10, places=10)
        self.assertEqual(clipped, 0)

    def test_clipping_advantages(self):
        a, raw, count = r.compute_advantages([10., -10.], -1.5)
        self.assertEqual(a, [1., -1.])
        self.assertEqual(count, 2)
        self.assertEqual(raw, [11.5, -8.5])

    def test_scenario_prior_and_state_validation(self):
        st = r.new_baseline_state()
        r.observe_completed_episode(st, 'A', [-1.5])
        r.observe_completed_episode(st, 'B', [-1.2])
        b, source = r.predict_baseline(st, 'A')
        self.assertEqual(source, 'scenario_global_blend')
        self.assertGreater(b, -1.5)
        self.assertLess(b, -1.2)
        st['version'] = 'incorrect'
        with self.assertRaises(ValueError):
            r.validate_baseline_state(st)

    def test_rose_score_loss_monotonic(self):
        rewards = []
        for rose in (60, 50, 40, 30, 20):
            rewards.append(r.rose_peer_rewards(end(rose, [10, 10, 10]), 3)[0][0])
        self.assertEqual(rewards, sorted(rewards))


if __name__ == '__main__':
    unittest.main(verbosity=2)
