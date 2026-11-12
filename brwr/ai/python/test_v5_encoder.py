from __future__ import annotations
import copy
import math
import unittest

import train
import v5_encoder as v5


class V5EncoderTests(unittest.TestCase):
    def setUp(self):
        self.obs = {'players': [{'power': 1, 'hand': [
            {'id': 'lightning_bolt'}, {'id': 'wither'}, {'id': 'drums_of_war'}]}],
                    'pending_input': {'hand': [{'hand_index': i, 'id': name} for i, name in
                                               enumerate(('lightning_bolt', 'wither', 'drums_of_war'))]}}
        self.decision = {'player_index': 0, 'type': 'preparation', 'substep': ''}

    def test_original_features_are_identical(self):
        option = {'detail': {'spells': ['wither']}, 'payload': {'quick_hand_index': 1}}
        original = train.encode_action(self.obs, self.decision, option, 1, 5)
        extended = v5.encode_action(self.obs, self.decision, option, 1, 5)
        self.assertEqual(len(extended), 384)
        self.assertEqual(extended[:128], original)

    def test_spell_combinations_have_different_semantics(self):
        a = {'detail': {'spells': ['wither', 'lightning_bolt']}, 'payload': {}}
        b = {'detail': {'spells': ['wither', 'drums_of_war']}, 'payload': {}}
        self.assertNotEqual(v5.semantic_features(self.obs, self.decision, a),
                            v5.semantic_features(self.obs, self.decision, b))

    def test_target_room_distinction(self):
        a = {'detail': {'tokens': ['room:throne']}, 'payload': {'selection': 'room:throne'}}
        b = {'detail': {'tokens': ['room:black_rose']}, 'payload': {'selection': 'room:black_rose'}}
        self.assertNotEqual(v5.semantic_features(self.obs, self.decision, a),
                            v5.semantic_features(self.obs, self.decision, b))

    def test_process_ids_not_semantic(self):
        a = {'detail': {'tokens': ['hand:-9223371891295645547'], 'instance': -9223371891295645547},
             'payload': {'selection': 'hand:-9223371891295645547'}}
        b = {'detail': {'tokens': ['hand:-9223371888888888888'], 'instance': -9223371888888888888},
             'payload': {'selection': 'hand:-9223371888888888888'}}
        self.assertEqual(v5.semantic_features(self.obs, self.decision, a),
                         v5.semantic_features(self.obs, self.decision, b))

    def test_selected_hand_indices_resolve_card_identity(self):
        a = {'detail': {}, 'payload': {'hand_index': 0}}
        b = {'detail': {}, 'payload': {'hand_index': 2}}
        self.assertNotEqual(v5.semantic_features(self.obs, self.decision, a),
                            v5.semantic_features(self.obs, self.decision, b))
        self.assertIn('resolved.hand_index=lightning_bolt', v5.semantic_terms(self.obs, self.decision, a))

    def test_side_movement_distinction(self):
        a = {'detail': {'action': {'type': 'explore', 'destination_room_ids': ['armory'],
                                   'activate_room_after_movement': False}}, 'payload': {}}
        b = {'detail': {'action': {'type': 'explore', 'destination_room_ids': ['library'],
                                   'activate_room_after_movement': True}}, 'payload': {}}
        self.assertNotEqual(v5.semantic_features(self.obs, self.decision, a),
                            v5.semantic_features(self.obs, self.decision, b))

    def test_deterministic(self):
        a = {'detail': {'kind': 'explore', 'action': {'type': 'attack', 'damage': 3}},
             'payload': {'ready_dark_sides': [True, False]}}
        b = {'payload': {'ready_dark_sides': [True, False]},
             'detail': {'action': {'damage': 3, 'type': 'attack'}, 'kind': 'explore'}}
        self.assertEqual(v5.semantic_features(self.obs, self.decision, a),
                         v5.semantic_features(self.obs, self.decision, b))


if __name__ == '__main__':
    unittest.main(verbosity=2)
