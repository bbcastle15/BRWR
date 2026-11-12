"""Read-only deterministic unit tests for reward v5-R1 and baseline semantics."""
import copy
import math
import unittest

import v5_reward_v1 as r


def end(rose, own, winner=-1):
    return {'winner': winner, 'scores': [
        {'player_index': -1, 'total': rose},
        *[{'player_index': i, 'total': score} for i, score in enumerate(own)]
    ]}


class RewardTests(unittest.TestCase):
    def test_rose_margin_priority_over_small_peer_advantage(self):
        worse = r.rose_peer_rewards(end(30, [10, 12, 10]), 3)[0]
        better = r.rose_peer_rewards(end(30, [20, 12, 10]), 3)[0]
        self.assertGreater(better[0] - worse[0], 0.10)
        # Two point peer advantage changes reward by much less than 10 points to BR.
        tie = r.rose_peer_rewards(end(30, [12, 12, 12]), 3)[0]
        self.assertLess(abs(worse[1] - tie[1]), 0.02)
        self.assertLess(abs(worse[1] - tie[1]), better[0] - worse[0])

    def test_win_dominates(self):
        losing, _ = r.rose_peer_rewards(end(30, [31, 10], winner=-1), 2)
        winning, _ = r.rose_peer_rewards(end(30, [31, 10], winner=0), 2)
        self.assertAlmostEqual(winning[0] - losing[0], 3.0)

    def test_incorrect_or_missing_scoreboard_rejected(self):
        for game in [end(30, [1, 2]) | {'scores': [{'player_index': 0, 'total': 1}]},
                     end(30, [1, 2]) | {'scores': [{'player_index': -1, 'total': 30},
                                                       {'player_index': 0, 'total': math.nan},
                                                       {'player_index': 1, 'total': 2}]},
                     end(30, [1, 2]) | {'winner': 100}]:
            with self.assertRaises(ValueError):
                r.rose_peer_rewards(game, 2)

    def test_first_game_calibration_only(self):
        state = r.new_baseline_state()
        key = r.scenario_key(3, 'none', 'apprentice')
        baseline, source = r.predict_baseline(state, key)
        self.assertIsNone(baseline)
        self.assertEqual(source, 'initial_calibration')
        self.assertEqual(r.compute_advantages([-1.4, -1.2], baseline), ([], [], 0))
        r.observe_completed_episode(state, key, [-1.4, -1.2])
        baseline, source = r.predict_baseline(state, key)
        self.assertAlmostEqual(baseline, -1.3)
        self.assertNotEqual(source, 'initial_calibration')

    def test_current_game_does_not_affect_baseline(self):
        state = r.new_baseline_state()
        r.observe_completed_episode(state, 'old', [-1.5, -1.5])
        frozen = copy.deepcopy(state)
        b, _ = r.predict_baseline(state, 'new')
        a, raw, _ = r.compute_advantages([-1.4, -1.1, -1.3], b)
        self.assertAlmostEqual(b, -1.5)
        self.assertGreater(a[1], a[0])
        self.assertEqual(state, frozen)
        self.assertAlmostEqual(raw[1], 0.4)

    def test_clip_and_scenario_prior(self):
        state = r.new_baseline_state()
        r.observe_completed_episode(state, 'A', [-1.7])
        r.observe_completed_episode(state, 'B', [-1.3])
        b, source = r.predict_baseline(state, 'A')
        self.assertEqual(source, 'scenario_global_blend')
        self.assertTrue(-1.7 < b < -1.3)
        adv, raw, n = r.compute_advantages([3.0, -5.0], b)
        self.assertEqual(adv, [1.0, -1.0])
        self.assertEqual(n, 2)
        self.assertNotEqual(raw, adv)

    def test_magical_score_from_realistic_terminal(self):
        # Same format for normal Black Rose and Possessed Avatar (index -1).
        example = end(43, [14, 18, 16])
        reward, info = r.rose_peer_rewards(example, 3)
        self.assertEqual(info['rose_score'], 43)
        self.assertEqual(info['best_margin_vs_rose'], -25)
        self.assertEqual(len(reward), 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
