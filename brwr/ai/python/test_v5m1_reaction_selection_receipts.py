#!/usr/bin/env python3
"""Strict board-trigger receipt provenance: Stinging Sand game 198 regression."""
from __future__ import annotations
import copy
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path

try:
    import v5_reward_v3 as reward
except ModuleNotFoundError:
    reward = types.ModuleType('v5_reward_v3')
    reward.SPELL_EFFECT_BONUS = 0.005
    reward.REACTION_EFFECT_BONUS = 0.007
    sys.modules['v5_reward_v3'] = reward

import v5m1_effect_receipts as receipts


def record(step, player, request_type, detail, *, label='', payload=None):
    return {'record_type': 'transition', 'step': step, 'player_index': player,
            'request_type': request_type, 'selected_candidate_id': 0,
            'legal_candidates': [{'id': 0, 'label': label, 'detail': detail,
                                  'payload': payload if payload is not None else {}}]}


def game198_records():
    # Extracted shape of the real Game 198 event, deliberately minimal.
    return [
        record(1, 0, 'action_activation_step',
               {'action': {'type': 'spell'},
                'descriptor': {'kind': 'cast', 'spell': {'id': 'branding', 'use_dark_side': False}}},
               label='Cast Branding'),
        record(2, 0, 'effect_choice',
               {'card_kind': 'spells', 'board_player_index': 0,
                'id': 'stinging_sand', 'slot_id': 'Q'},
               label='Select Stinging Sand', payload={'ai_select': 'arm:-9223371787260129185'}),
        record(3, 0, 'effect_choice', {'selected_count': 1},
               label='Confirm selection', payload={'ai_finish': True}),
    ]


def event(kind='reaction', spell='stinging_sand', step=3, player=0, spell_type='trap', origin='direct'):
    return {'kind': kind, 'spell_id': spell, 'spell_type': spell_type,
            'step': step, 'player_index': player,
            'cast_origin': origin, 'origin_room_id': '', 'use_dark_side': None,
            'material_change': True, 'prevention': False}


def parse(transitions=None, events=None):
    if transitions is None:
        transitions = game198_records()
    if events is None:
        events = [event()]
    doc = {'schema': receipts.SCHEMA, 'seed': 20350299,
           'decisions': len(transitions), 'uncredited': 0, 'events': events}
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'receipt.json'
        path.write_text(json.dumps(doc), encoding='utf-8')
        return receipts.load_effect_bonuses(
            path, seed=20350299, decisions=len(transitions), transitions=transitions, bots=4)


class ReactionChoiceTests(unittest.TestCase):
    def test_game198_stinging_sand_reward_goes_to_choice_not_confirm(self):
        bonus, stats = parse()
        self.assertEqual(list(bonus), [2])
        self.assertAlmostEqual(bonus[2], reward.REACTION_EFFECT_BONUS)
        self.assertEqual(stats['effective_reactions'], 1)
        self.assertEqual(stats['reaction_card_selections'], 1)
        self.assertEqual(stats['room_auto_casts'], 0)

    def test_direct_cast_still_strict_and_credited_directly(self):
        steps = [record(1, 0, 'action_activation_step',
                        {'action': {'type': 'spell'},
                         'descriptor': {'kind': 'cast', 'spell': {'id': 'branding', 'use_dark_side': False}}})]
        e = event(kind='spell', spell='branding', step=1, spell_type='contingency')
        e['use_dark_side'] = False
        bonus, stats = parse(steps, [e])
        self.assertEqual(list(bonus), [1])
        self.assertEqual(stats['reaction_card_selections'], 0)

    def test_other_spell_cannot_claim_bonus(self):
        records = game198_records()
        records[1]['legal_candidates'][0]['detail']['id'] = 'sarcophagus'
        with self.assertRaisesRegex(ValueError, 'no verified reaction selection'):
            parse(records)

    def test_other_player_cannot_claim_bonus(self):
        records = game198_records()
        records[1]['legal_candidates'][0]['detail']['board_player_index'] = 2
        with self.assertRaises(ValueError): parse(records)

    def test_wrong_player_in_selection_step_rejected(self):
        records = game198_records()
        records[1]['player_index'] = 2
        with self.assertRaises(ValueError): parse(records)

    def test_no_confirmation_rejected(self):
        records = game198_records()
        records[2]['legal_candidates'][0]['payload'] = {'ai_finish': False}
        with self.assertRaises(ValueError): parse(records)

    def test_cancel_rejected(self):
        records = game198_records()
        records[2]['legal_candidates'][0]['detail']['selected_count'] = 0
        with self.assertRaises(ValueError): parse(records)

    def test_selection_must_be_a_spell_board_card(self):
        records = game198_records()
        records[1]['legal_candidates'][0]['detail']['card_kind'] = 'equipment'
        with self.assertRaises(ValueError): parse(records)

    def test_other_choice_not_accepted(self):
        records = game198_records()
        records[1]['legal_candidates'][0]['payload']['ai_select'] = 'room:arena'
        with self.assertRaises(ValueError): parse(records)

    def test_no_reward_for_unproven_spell_event(self):
        with self.assertRaises(ValueError): parse(events=[event(kind='spell')])

    def test_reaction_must_be_trap_or_protection(self):
        with self.assertRaises(ValueError): parse(events=[event(spell_type='combat')])

    def test_no_material_change_no_reward(self):
        e=event();e['material_change']=False
        with self.assertRaises(ValueError): parse(events=[e])

    def test_confirmation_must_be_immediately_after_card_selection(self):
        records=game198_records()
        records.insert(2,record(3,0,'effect_choice',{'other':'choice'},label='Other'))
        records[3]['step']=4
        with self.assertRaises(ValueError): parse(records,[event(step=4)])

    def test_no_reaction_retrocredit_for_momentum(self):
        records=game198_records()
        records[1]['request_type']='action_activation_step'
        with self.assertRaises(ValueError): parse(records)

    def test_batch_bonus_cap_preserved(self):
        bonus, stats=parse(events=[event() for _ in range(9)])
        self.assertAlmostEqual(bonus[2],0.04)
        self.assertEqual(stats['reaction_card_selections'],9)

    def test_missing_candidate_fails_closed(self):
        records=game198_records()
        records[1]['selected_candidate_id']=99
        with self.assertRaises(ValueError): parse(records)

    def test_second_spell_in_same_step_does_not_pass(self):
        with self.assertRaises(ValueError): parse(events=[event(),event(spell='sarcophagus')])

    def test_side_mismatch_still_blocks_direct_cast(self):
        steps=[record(1,0,'action_activation_step',
                      {'action': {'type': 'spell'},
                       'descriptor': {'kind':'cast','spell':{'id':'branding','use_dark_side':False}}})]
        e=event(kind='spell',spell='branding',step=1,spell_type='contingency')
        e['use_dark_side']=True
        with self.assertRaises(ValueError): parse(steps,[e])


def game399_records():
    """Minimal faithful transcription of game399 step157 from the diagnostic."""
    token = 'arm:-9223371769610497869'
    return [{
        'record_type': 'transition', 'step': 157, 'player_index': 3,
        'request_type': 'effect_choice', 'selected_candidate_id': 1,
        'legal_candidates': [
            {'id': 0, 'label': 'Select none', 'detail': {}, 'payload': {'selection': ''}},
            {'id': 1, 'label': token, 'detail': {
                'id': 'sarcophagus', 'name': 'Sarcophagus', 'card_kind': 'spells',
                'board_player_index': 3, 'token': token, 'slot_id': 'III'
            }, 'payload': {'selection': token}}
        ]
    }]


def game399_event():
    # events[7] from game399_receipts.json in the uploaded evidence bundle.
    return {'cast_origin': 'direct', 'kind': 'reaction', 'material_change': True,
            'origin_room_id': '', 'player_index': 3, 'prevention': True,
            'spell_id': 'sarcophagus', 'spell_type': 'protection', 'step': 157,
            'use_dark_side': None}


def parse399(selected_record=None, event399=None):
    # Surround the real selected record with harmless transitions; their
    # contents cannot be used to infer a Cast or a reaction reward.
    records = [record(i, i % 4, 'preparation', {}, label='Unrelated')
               for i in range(1, 157)]
    records.append(copy.deepcopy(game399_records()[0] if selected_record is None else selected_record))
    rec = copy.deepcopy(game399_event() if event399 is None else event399)
    return parse(records, [rec])


class Game399SingleStepReactionTests(unittest.TestCase):
    def test_game399_sarcophagus_prevention_rewarded_at_selected_step(self):
        bonuses, stats = parse399()
        self.assertEqual(list(bonuses), [157])
        self.assertAlmostEqual(bonuses[157], reward.REACTION_EFFECT_BONUS)
        self.assertEqual(stats['effective_reactions'], 1)
        self.assertEqual(stats['reaction_card_selections'], 1)

    def test_game198_two_step_still_credited_at_card_choice(self):
        bonus, stats = parse()
        self.assertEqual(list(bonus), [2])
        self.assertEqual(stats['reaction_card_selections'], 1)

    def test_opt_out_never_rewarded(self):
        r=game399_records()[0];r['selected_candidate_id']=0
        with self.assertRaisesRegex(ValueError,'no verified reaction selection'):parse399(r)

    def test_no_opt_out_fails_closed(self):
        r=game399_records()[0];r['legal_candidates'][0]['label']='Discard none'
        with self.assertRaises(ValueError):parse399(r)

    def test_owner_must_match(self):
        r=game399_records()[0];r['legal_candidates'][1]['detail']['board_player_index']=0
        with self.assertRaises(ValueError):parse399(r)

    def test_other_player_transition_fails(self):
        r=game399_records()[0];r['player_index']=0
        with self.assertRaises(ValueError):parse399(r)

    def test_selected_spell_must_match(self):
        e=game399_event();e['spell_id']='branding'
        with self.assertRaises(ValueError):parse399(event399=e)

    def test_mismatched_selection_token_fails(self):
        r=game399_records()[0];r['legal_candidates'][1]['payload']['selection']='arm:unrelated'
        with self.assertRaises(ValueError):parse399(r)

    def test_mismatched_label_fails(self):
        r=game399_records()[0];r['legal_candidates'][1]['label']='Select Sarcophagus'
        with self.assertRaises(ValueError):parse399(r)

    def test_missing_board_slot_fails(self):
        r=game399_records()[0];r['legal_candidates'][1]['detail']['slot_id']=''
        with self.assertRaises(ValueError):parse399(r)

    def test_nonspell_card_fails(self):
        r=game399_records()[0];r['legal_candidates'][1]['detail']['card_kind']='equipment'
        with self.assertRaises(ValueError):parse399(r)

    def test_other_request_type_fails(self):
        r=game399_records()[0];r['request_type']='action_activation_step'
        with self.assertRaises(ValueError):parse399(r)

    def test_missing_selection_candidate_fails(self):
        r=game399_records()[0];r['selected_candidate_id']=3
        with self.assertRaises(ValueError):parse399(r)

    def test_unproven_combat_spell_fails(self):
        e=game399_event();e['kind']='spell';e['spell_type']='combat'
        with self.assertRaises(ValueError):parse399(event399=e)

    def test_no_material_or_prevention_fails(self):
        e=game399_event();e['material_change']=False;e['prevention']=False
        with self.assertRaises(ValueError):parse399(event399=e)

    def test_negative_step_fails(self):
        e=game399_event();e['step']=-1
        with self.assertRaises(ValueError):parse399(event399=e)

    def test_no_false_credit_for_momentum_candidate(self):
        r=game399_records()[0]
        r['legal_candidates'][1]['detail']={'action':{'type':'momentum'}, 'id':'sarcophagus'}
        with self.assertRaises(ValueError):parse399(r)

    def test_unknown_extra_candidate_fails(self):
        r=game399_records()[0]
        r['legal_candidates'].append({'id':2,'label':'room:arena', 'detail':{'token':'room:arena'},'payload':{'selection':'room:arena'}})
        with self.assertRaises(ValueError):parse399(r)

    def test_multi_armed_cards_allowed_if_all_valid(self):
        r=game399_records()[0]
        other=copy.deepcopy(r['legal_candidates'][1]);other['id']=2
        other['label']='arm:another';other['payload']['selection']='arm:another'
        other['detail']['id']='another_spell';other['detail']['token']='arm:another'
        r['legal_candidates'].append(other)
        bonus,stats=parse399(r)
        self.assertEqual(list(bonus),[157])
        self.assertEqual(stats['reaction_card_selections'],1)


if __name__=='__main__':
    unittest.main(verbosity=2)
