import copy
import json
import tempfile
import unittest
from pathlib import Path
import v5_reward_v3 as r
import v5_r3_effect_receipts as receipts


def end(rose, scores, winner=-1):
    return {'winner': winner, 'scores': [{'player_index': -1, 'total': rose}] +
            [{'player_index': i, 'total': v} for i, v in enumerate(scores)]}


class TestV5R3(unittest.TestCase):
    def test_points_more_important_than_spell(self):
        a, _ = r.rose_peer_rewards(end(40, [0, 0, 0]), 3)
        b, _ = r.rose_peer_rewards(end(40, [1, 0, 0]), 3)
        self.assertAlmostEqual(b[0]-a[0], .030+.015+.002)
        self.assertGreater(b[0]-a[0], 7*r.SPELL_EFFECT_BONUS)

    def test_rose_more_important_than_peers(self):
        a, _ = r.rose_peer_rewards(end(40, [10, 10, 10]), 3)
        b, _ = r.rose_peer_rewards(end(30, [10, 10, 10]), 3)
        c, _ = r.rose_peer_rewards(end(40, [10, 8, 8]), 3)
        self.assertAlmostEqual(b[0]-a[0], .15)
        self.assertAlmostEqual(c[0]-a[0], .004)

    def test_baseline_not_in_same_game(self):
        state = r.new_baseline_state(); key = r.scenario_key(3, 'none','apprentice')
        self.assertIsNone(r.predict_baseline(state,key)[0])
        r.observe_completed_episode(state,key,[-1.7, -1.4, -1.5])
        frozen = copy.deepcopy(state)
        a, raw, _ = r.compute_advantages([-1.4,-1.7], r.predict_baseline(state,key)[0])
        self.assertGreater(a[0],0); self.assertLess(a[1],0)
        self.assertEqual(frozen,state)

    def test_receipts_strict_owner_step_and_effect(self):
        candidates = [{'detail': {'action': {'type':'quick'},'descriptor':{'kind':'cast'}},'id':0}]
        transitions = [{'step':1,'player_index':0,'selected_candidate_id':0,'legal_candidates':candidates},
                       {'step':2,'player_index':1,'selected_candidate_id':0,'legal_candidates':candidates}]
        doc = {'schema':receipts.SCHEMA,'seed':123,'decisions':2,'uncredited':0,'events':[
            {'step':1,'player_index':0,'kind':'spell','spell_type':'combat','spell_id':'fire','material_change':True,'prevention':False},
            {'step':1,'player_index':0,'kind':'reaction','spell_type':'trap','spell_id':'snare','material_change':True,'prevention':False}]}
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'receipt.json';path.write_text(json.dumps(doc))
            bonus,stats=receipts.load_effect_bonuses(path, seed=123,decisions=2,transitions=transitions,bots=2)
            self.assertAlmostEqual(bonus[1],.012)
            self.assertEqual(stats['effective_reactions'],1)
            doc['events'][0]['material_change']=False
            path.write_text(json.dumps(doc))
            with self.assertRaises(ValueError): receipts.load_effect_bonuses(path,seed=123,decisions=2,transitions=transitions,bots=2)
            doc['events'][0]['material_change']=True;doc['events'][0]['player_index']=1
            path.write_text(json.dumps(doc))
            with self.assertRaises(ValueError): receipts.load_effect_bonuses(path,seed=123,decisions=2,transitions=transitions,bots=2)

    def test_no_bonus_without_receipts(self):
        with self.assertRaises(ValueError):
            receipts.load_effect_bonuses(Path('nonexistent.receipts.json'), seed=1, decisions=1, transitions=[{}], bots=2)

if __name__=='__main__': unittest.main(verbosity=2)
