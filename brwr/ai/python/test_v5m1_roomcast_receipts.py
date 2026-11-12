#!/usr/bin/env python3
"""Read-only V5M1 free room-cast provenance / receipt tests."""
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path

# On the real BRWR install the existing v5_reward_v3 module is used.
try:
    import v5_reward_v3 as reward
except ModuleNotFoundError:
    reward = types.ModuleType('v5_reward_v3')
    reward.SPELL_EFFECT_BONUS = 0.005
    reward.REACTION_EFFECT_BONUS = 0.007
    sys.modules['v5_reward_v3'] = reward

import v5m1_effect_receipts as r3

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def step(kind, *, owner=3, room='arena', after=True, spell='tearing', dark=False):
    if kind == 'cast':
        action = {'type': 'spell'}
        desc = {'kind': 'cast', 'spell': {'id': spell, 'use_dark_side': dark}}
    elif kind == 'explore':
        action = {'type': 'explore', 'activate_room_before_movement': not after,
                  'activate_room_after_movement': after}
        desc = {'kind': 'explore', 'final_room_id': room}
    elif kind == 'fight':
        action = {'type': 'fight', 'perform_room_activation': True}
        desc = {'kind': 'fight'}
    else:
        action = {'type': kind}
        desc = {'kind': kind}
    return {'step': 1, 'player_index': owner,
            'request_type': 'action_activation_step', 'selected_candidate_id': 0,
            'legal_candidates': [{'id': 0, 'detail': {'action': action, 'descriptor': desc}}]}


def receipt(*, owner=3, origin='room_cast_next_ready', room='arena', spell='tearing', dark=False):
    return {'step': 1, 'player_index': owner, 'spell_id': spell, 'spell_type': 'contingency',
            'kind': 'spell', 'material_change': True, 'prevention': False,
            'cast_origin': origin, 'origin_room_id': room, 'use_dark_side': dark}


class ProvenanceTests(unittest.TestCase):
    def check(self, transition, events, matches=True):
        doc = {'schema': r3.SCHEMA, 'seed': 20350232, 'decisions': 1,
               'uncredited': 0, 'events': events}
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'receipts.json'
            p.write_text(json.dumps(doc), encoding='utf-8')
            if matches:
                return r3.load_effect_bonuses(p, seed=20350232, decisions=1,
                                              transitions=[transition], bots=5)
            with self.assertRaises(ValueError):
                r3.load_effect_bonuses(p, seed=20350232, decisions=1,
                                       transitions=[transition], bots=5)

    def test_game131_arena_room_auto_cast_is_credited(self):
        bonus, summary = self.check(step('explore'), [receipt()])
        self.assertAlmostEqual(bonus[1], reward.SPELL_EFFECT_BONUS)
        self.assertEqual(summary['room_auto_casts'], 1)

    def test_fight_activation_auto_cast_is_credited(self):
        _, summary = self.check(step('fight'), [receipt()])
        self.assertEqual(summary['room_auto_casts'], 1)

    def test_direct_tearing_cast_is_credited(self):
        _, summary = self.check(step('cast'), [receipt(origin='direct', room='')])
        self.assertEqual(summary['room_auto_casts'], 0)

    def test_explore_without_proven_origin_never_rewarded(self):
        self.check(step('explore'), [receipt(origin='direct')], False)

    def test_room_cast_cannot_claim_wrong_destination(self):
        self.check(step('explore', room='observatory'), [receipt()], False)

    def test_room_cast_must_activate_room(self):
        t = step('explore')
        t['legal_candidates'][0]['detail']['action']['activate_room_after_movement'] = False
        self.check(t, [receipt()], False)

    def test_room_cast_cannot_claim_momentum(self):
        self.check(step('momentum'), [receipt()], False)

    def test_room_cast_cannot_claim_other_owner(self):
        self.check(step('explore', owner=2), [receipt(owner=3)], False)

    def test_direct_cast_cannot_claim_other_spell(self):
        self.check(step('cast', spell='entropy'), [receipt(origin='direct', room='')], False)

    def test_direct_cast_side_is_verified(self):
        self.check(step('cast', dark=True), [receipt(origin='direct', dark=False, room='')], False)

    def test_unknown_cast_origin_rejected(self):
        self.check(step('explore'), [receipt(origin='unknown')], False)

    def test_no_material_effect_never_rewarded(self):
        e = receipt()
        e['material_change'] = False
        self.check(step('explore'), [e], False)

    def test_cap_for_repeated_bonuses(self):
        bonus, summary = self.check(step('explore'), [receipt() for _ in range(10)])
        self.assertLessEqual(bonus[1], 0.04)
        self.assertEqual(summary['room_auto_casts'], 10)

    def test_generated_game_patcher_is_idempotency_guarded(self):
        from build_v5m1_roomcast_provenance import make_game
        sample = '''extends Node2D
var _brwr_r3_decision_step: int = 0
func submit_action_activation_step(player_index: int, token: String) -> bool:
	var action: Dictionary = selected.get("action", {}).duplicate(true)
	if action.is_empty():
		return false

	clear_player_input()
	return true
func cast_next_ready_spell(player_index: int, context: Dictionary = {}) -> bool:
	if ready_spell == null:
		print("cast_next_ready_spell: no Ready Spell")
		return false

	return queue_resolution({
		"type": "spell_cast"
	})
func _brwr_r3_emit(frame: Dictionary, context: Dictionary, triggered: bool) -> void:
	_brwr_r3_effect_events.append({
		"spell_type": spell_type,
		"kind": "reaction" if reaction else "spell",
		"material_change": material_change,
		"prevention": prevention
	})
'''
        patched = make_game(sample)
        self.assertIn('_brwr_v5m1_cast_origin', patched)
        self.assertIn('func _brwr_v5m1_room_cast_provenance(', patched)
        self.assertIn('origin_context["_brwr_v5m1_action_source_step"] = _brwr_r3_decision_step', patched)
        self.assertIn('context["_brwr_r3_cast_decision"] = int(proven_room_cast.get("source_step", -1))', patched)
        with self.assertRaises(RuntimeError):
            make_game(patched)


    def test_game311_step423_is_correct_owner_room(self):
        # Game 311: player 2 selected Explore -> Arena at step 423;
        # at 424 player 0 was deciding whether to trigger another Spell.
        transition = step('explore', owner=2, room='arena')
        transition['step'] = 423
        event = receipt(owner=2, room='arena', spell='ineluctable_pain', dark=True)
        event['step'] = 423
        transitions = [{'step': i, 'player_index': 0, 'request_type': 'effect_choice'}
                       for i in range(1, 440)]
        transitions[422] = transition
        transitions[423] = {'step': 424, 'player_index': 0, 'request_type': 'trigger_decision'}
        doc = {'schema': r3.SCHEMA, 'seed': 20350412, 'decisions': 439,
               'uncredited': 0, 'events': [event]}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'receipts.json'
            path.write_text(json.dumps(doc), encoding='utf-8')
            bonuses, summary = r3.load_effect_bonuses(
                path, seed=20350412, decisions=439, transitions=transitions, bots=3)
        self.assertIn(423, bonuses)
        self.assertNotIn(424, bonuses)
        self.assertEqual(summary['room_auto_casts'], 1)

    def test_game311_late_step_must_not_steal_another_player(self):
        self.check(step('explore', owner=0, room='arena'),
                   [receipt(owner=2, spell='ineluctable_pain', dark=True)], False)

    def test_game311_wrong_room_must_fail(self):
        self.check(step('explore', owner=2, room='garden'),
                   [receipt(owner=2, spell='ineluctable_pain', dark=True)], False)

    def test_game311_receipt_claiming_trigger_decision_is_rejected(self):
        t = step('explore', owner=2, room='arena')
        t['request_type'] = 'trigger_decision'
        self.check(t, [receipt(owner=2, spell='ineluctable_pain', dark=True)], False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
