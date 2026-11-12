#!/usr/bin/env python3
"""Patch only generated AI Game and v5 worker to emit causally-attributed receipts.

Must run after train_optimized_v5.preflight() regenerates ai/game_school_cached.gd
and ai/ai_policy_school_v5_match.gd. Never touches game.gd or game.tscn.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GAME = ROOT / 'ai/game_school_cached.gd'
WORKER = ROOT / 'ai/ai_policy_school_v5_match.gd'
METHODS = ROOT / 'r3_game_effect_methods.gd.inc'


def replace_once(text, a, b, desc):
    if text.count(a) != 1:
        raise RuntimeError(f'R3_BUILD_STOP {desc}: expected one anchor, found {text.count(a)}')
    return text.replace(a, b, 1)


def patch_func(text, name, before, after):
    start_tag = f'func {name}('
    if text.count(start_tag) != 1:
        raise RuntimeError(f'R3_BUILD_STOP missing/nonunique function {name}')
    start = text.index(start_tag)
    end = text.find('\nfunc ', start + len(start_tag))
    if end < 0:
        raise RuntimeError(f'R3_BUILD_STOP cannot find end of {name}')
    body = text[start:end]
    body = replace_once(body, before, after, f'{name} insertion')
    return text[:start] + body + text[end:]


def make_game(source):
    if 'func _brwr_r3_snapshot(' in source:
        raise RuntimeError('R3_BUILD_STOP game already instrumented; rebuild with v5 preflight')
    for name in ('refresh_all_player_boards', 'refresh_player_board', '_refresh_damage_boards'):
        pos = source.find('func ' + name + '(')
        if pos < 0 or 'if not enable_beta_hud:\n\t\treturn' not in source[pos:pos+350]:
            raise RuntimeError('R3_BUILD_STOP guard missing ' + name)
    source = replace_once(source, 'extends Node2D\n',
        'extends Node2D\n'
        '\nvar _brwr_r3_decision_step: int = 0\n'
        'var _brwr_r3_room_activations: int = 0\n'
        'var _brwr_r3_uncredited: int = 0\n'
        'var _brwr_r3_effect_events: Array = []\n', 'AI cached game extends')
    source = patch_func(source, 'process_spell_cast_resolution',
        '\t\t\tcontext["caster_room_id"] = player.mage.room_id\n\t\t\tresolution["context"] = context',
        '\t\t\tcontext["caster_room_id"] = player.mage.room_id\n'
        '\t\t\tif not context.has("_brwr_r3_cast_decision"):\n'
        '\t\t\t\tcontext["_brwr_r3_cast_decision"] = _brwr_r3_decision_step\n'
        '\t\t\tresolution["context"] = context')
    source = patch_func(source, 'process_spell_resolution_frame',
        '\t\t\tresolution["step"] = "next_sequence"',
        '\t\t\tresolution["_brwr_r3_before"] = _brwr_r3_snapshot()\n'
        '\t\t\tresolution["step"] = "next_sequence"')
    source = patch_func(source, 'process_spell_resolution_frame',
        '\t\t"reveal":\n\n\t\t\tresolution["step"] = "done"',
        '\t\t"reveal":\n\n'
        '\t\t\t_brwr_r3_emit(resolution, context, false)\n'
        '\t\t\tresolution["step"] = "done"')
    source = patch_func(source, 'process_trigger_spell_resolution',
        '\t\t"prepare_effects":\n\t\t\tvar context: Dictionary = resolution.context',
        '\t\t"prepare_effects":\n\t\t\tvar context: Dictionary = resolution.context\n'
        '\t\t\tif not resolution.has("_brwr_r3_before"):\n'
        '\t\t\t\tresolution["_brwr_r3_before"] = _brwr_r3_snapshot()')
    source = patch_func(source, 'process_trigger_spell_resolution',
        '\t\t"after_effects":\n\t\t\tvar context: Dictionary = resolution.get("context", {})',
        '\t\t"after_effects":\n\t\t\tvar context: Dictionary = resolution.get("context", {})\n'
        '\t\t\t_brwr_r3_emit(resolution, context, true)')
    source = patch_func(source, 'process_room_activation_resolution',
        '\t\t\troom.mark_activated()',
        '\t\t\troom.mark_activated()\n\t\t\t_brwr_r3_room_activations += 1')
    methods = METHODS.read_text(encoding='utf-8')
    source += '\n\n' + methods
    return source


def make_worker(source):
    if 'BRWR_R3_RECEIPTS_FILE' in source:
        raise RuntimeError('R3_BUILD_STOP worker already instrumented; rebuild with v5 preflight')
    source = replace_once(source,
        '\t\t\t\tif not bridge.step(i, choice, str(decision.get("signature", ""))):',
        '\t\t\t\tgame._brwr_r3_decision_step = decisions + 1\n'
        '\t\t\t\tif not bridge.step(i, choice, str(decision.get("signature", ""))):',
        'bridge step marker')
    marker = '\toutput_file.close()\n\tprint("AI_EPISODE_COMPLETE seed="'
    report = '''\toutput_file.close()
	var receipt_path: String = output_path + ".r3_receipts.json"
	var receipt_file: FileAccess = FileAccess.open(receipt_path, FileAccess.WRITE)
	if receipt_file == null:
		_fail("R3 receipt file cannot be opened: " + receipt_path)
		return
	receipt_file.store_string(JSON.stringify({
		"schema": "brwr_v5_r3_effect_receipts_v1",
		"seed": match_seed,
		"decisions": decisions,
		"uncredited": game._brwr_r3_uncredited,
		"events": game._brwr_r3_effect_events
	}))
	receipt_file.close()
	print("BRWR_R3_RECEIPTS_FILE ", receipt_path)
	print("AI_EPISODE_COMPLETE seed="'''
    source = replace_once(source, marker, report, 'write receipts at episode end')
    return source


def main():
    for p in (GAME, WORKER, METHODS):
        if not p.is_file():
            raise RuntimeError('R3_BUILD_STOP missing ' + str(p))
    game_before = GAME.read_text(encoding='utf-8-sig')
    worker_before = WORKER.read_text(encoding='utf-8-sig')
    game_after = make_game(game_before)
    worker_after = make_worker(worker_before)
    # All validation before mutation, preserving files if a source anchor changes.
    GAME.write_bytes(game_after.encode('utf-8'))
    WORKER.write_bytes(worker_after.encode('utf-8'))
    print('V5R3_RECEIPTS_BUILD_OK isolated_game=1 worker_only=1 original_game_unchanged=1')

if __name__ == '__main__':
    main()
