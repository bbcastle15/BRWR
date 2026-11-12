#!/usr/bin/env python3
"""V5M1-only patch to AI generated cached Game after R3 receipt builder.

Instruments ONLY ai/game_school_cached.gd; production game.gd stays untouched.
Records proven provenance for spells auto-cast by a room's cast_next_ready_spell.
Crucial: preserves the decision step when the action was SELECTED, even if
trigger windows advance the global AI decision counter before the Spell resolves.
Unverifiable room casts are left uncredited, never attributed to another AI.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GAME = ROOT / 'ai/game_school_cached.gd'

HELPER = """
# V5M1: inspect the active resolution stack, never infer an auto-cast from
# a previously cast Spell or merely from the current step number.
func _brwr_v5m1_room_cast_provenance(player_index: int) -> Dictionary:
	var in_room_effect: bool = false
	for frame in resolution_stack:
		if str(frame.get("type", "")) == "effect_sequence" \\
		and str(frame.get("resolver_kind", "")) == "room":
			in_room_effect = true
			break
	if not in_room_effect:
		return {}
	for frame in resolution_stack:
		if str(frame.get("type", "")) != "room_activation":
			continue
		if int(frame.get("player_index", -1)) != player_index:
			continue
		var room_id: String = str(frame.get("room_id", ""))
		var room = get_room_by_id(room_id)
		if room == null:
			continue
		for effect_value in room.get_effects():
			if effect_value is Dictionary \\
			and str(effect_value.get("type", "")) == "cast_next_ready_spell":
				# This belongs to the original Explore/Fight Action, NOT the
				# global decision counter at the moment the nested Spell starts.
				var activation_context: Dictionary = frame.get("context", {})
				var source_step: int = int(activation_context.get("_brwr_v5m1_action_source_step", -1))
				return {"origin": "room_cast_next_ready", "room_id": room_id, "source_step": source_step}
	return {}
"""


def patch_function(text: str, name: str, original: str, replacement: str) -> str:
    tag = 'func ' + name + '('
    if text.count(tag) != 1:
        raise RuntimeError('ROOMCAST_PATCH_STOP missing/duplicate function: ' + name)
    start = text.index(tag)
    end = text.find('\nfunc ', start + len(tag))
    if end < 0:
        end = len(text)
    body = text[start:end]
    if body.count(original) != 1:
        raise RuntimeError('ROOMCAST_PATCH_STOP unexpected anchor in ' + name + ': ' + str(body.count(original)))
    return text[:start] + body.replace(original, replacement, 1) + text[end:]


def make_game(text: str) -> str:
    if 'func _brwr_v5m1_room_cast_provenance(' in text:
        raise RuntimeError('ROOMCAST_PATCH_STOP already patched; regenerate R3 Game first')
    if 'func _brwr_r3_emit(' not in text or 'var _brwr_r3_decision_step:' not in text:
        raise RuntimeError('ROOMCAST_PATCH_STOP missing R3 instrumentation')
    # The timestamp is captured at the real AI selection, before any nested
    # trigger, mandatory effect or target selection can advance the counter.
    action_anchor = """	if action.is_empty():
		return false

	clear_player_input()"""
    action_replacement = """	if action.is_empty():
		return false

	# V5M1 AI-only: causal decision origin survives suspended resolutions.
	if kind == "action":
		var selected_type: String = str(action.get("type", ""))
		if selected_type in ["explore", "fight"]:
			var origin_context: Dictionary = action.get("context", {}).duplicate(false)
			origin_context["_brwr_v5m1_action_source_step"] = _brwr_r3_decision_step
			action["context"] = origin_context

	clear_player_input()"""
    text = patch_function(text, 'submit_action_activation_step', action_anchor, action_replacement)
    anchor = """	if ready_spell == null:
		print("cast_next_ready_spell: no Ready Spell")
		return false

	return queue_resolution({"""
    replacement = """	if ready_spell == null:
		print("cast_next_ready_spell: no Ready Spell")
		return false

	# The rebuilt Arena and similar room effects may cast a prepared Spell
	# without the Mage choosing a Cast Action this step.
	var proven_room_cast: Dictionary = _brwr_v5m1_room_cast_provenance(player_index)
	context = context.duplicate(false)
	# Never inherit stale provenance from another effect context.
	context.erase("_brwr_v5m1_cast_origin")
	context.erase("_brwr_v5m1_origin_room_id")
	if not proven_room_cast.is_empty():
		context["_brwr_v5m1_cast_origin"] = str(proven_room_cast["origin"])
		context["_brwr_v5m1_origin_room_id"] = str(proven_room_cast["room_id"])
		# Fail closed on missing causal step: the R3 emitter will count
		# the effect as uncredited rather than assign it to another Mage.
		context["_brwr_r3_cast_decision"] = int(proven_room_cast.get("source_step", -1))

	return queue_resolution({"""
    text = patch_function(text, 'cast_next_ready_spell', anchor, replacement)
    anchor = """		"spell_type": spell_type,
		"kind": "reaction" if reaction else "spell",
		"material_change": material_change,
		"prevention": prevention"""
    replacement = """		"spell_type": spell_type,
		"kind": "reaction" if reaction else "spell",
		"material_change": material_change,
		"prevention": prevention,
		"cast_origin": str(context.get("_brwr_v5m1_cast_origin", "direct")),
		"origin_room_id": str(context.get("_brwr_v5m1_origin_room_id", "")),
		"use_dark_side": context.get("spell_use_dark_side", null)"""
    text = patch_function(text, '_brwr_r3_emit', anchor, replacement)
    return text + '\n' + HELPER


def main():
    if not GAME.is_file():
        raise RuntimeError('ROOMCAST_PATCH_STOP no generated R3 Game: ' + str(GAME))
    before = GAME.read_text(encoding='utf-8-sig')
    after = make_game(before)  # fail atomically before writes
    GAME.write_bytes(after.encode('utf-8'))
    print('V5M1_ROOMCAST_PROVENANCE_BUILD_OK generated_game_only=1 original_game_unchanged=1')


if __name__ == '__main__':
    main()
