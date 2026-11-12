#!/usr/bin/env python3
"""Isolated v5-only parity correction for numeric selection tokens.

Godot JSON numbers may be floats (0.0) even when Python parsed the same
original value as an integer (0). The v4 encoder hashes 'selection:'+str(...).
We override the inherited string formatter only in v5's derived encoder.
No weights, checkpoint, data, or base v4 file is touched.
"""
from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / 'ai' / 'ai_v5_semantic_encoder.gd'
START = '# BEGIN BRWR V5 NUMERIC SELECTION PARITY FIX'
END = '# END BRWR V5 NUMERIC SELECTION PARITY FIX'
INSERT = '''# BEGIN BRWR V5 NUMERIC SELECTION PARITY FIX
# Python renders integral numbers as "0", "3", ... when parsing JSON as int.
# Godot can parse the same numeric values as float and render "0.0", "3.0".
# This class alone overrides v4's categorical string formatter; v4 is untouched.
func _py_string(value: Variant) -> String:
\tif value is bool:
\t\treturn "True" if value else "False"
\tif value is float and is_finite(value) and absf(value) <= 9007199254740991.0:
\t\tif value == float(int(value)):
\t\t\treturn str(int(value))
\treturn str(value)
# END BRWR V5 NUMERIC SELECTION PARITY FIX

'''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true', help='Check whether the fix is already applied')
    args = parser.parse_args()
    if not TARGET.is_file():
        raise SystemExit(f'FIX_V5_STOP missing {TARGET.relative_to(ROOT)}')
    code = TARGET.read_text(encoding='utf-8')
    if START in code:
        if END not in code or code.count(START) != 1 or code.count(END) != 1:
            raise SystemExit('FIX_V5_STOP malformed existing fix')
        print('FIX_V5_NUMERIC_SELECTION_ALREADY_INSTALLED v4_unchanged=1 checkpoints_unchanged=1')
        return
    if args.check:
        raise SystemExit('FIX_V5_STOP fix not yet installed')
    marker = 'func encode_action(obs: Dictionary, decision: Dictionary, option: Dictionary, choice_index: int, total_options: int) -> PackedFloat32Array:'
    if code.count(marker) != 1 or not code.lstrip().startswith('# Experimental BRWR v5 encoder parity probe ONLY.'):
        raise SystemExit('FIX_V5_STOP unexpected encoder version; not patching unknown source')
    if 'extends "res://ai/ai_native_policy_v4.gd"' not in code:
        raise SystemExit('FIX_V5_STOP v5 encoder does not inherit expected v4 policy')
    if re.search(r'(?m)^func _py_string\(', code):
        raise SystemExit('FIX_V5_STOP existing _py_string override; manual inspection needed')
    new = code.replace(marker, INSERT + marker)
    if new == code:
        raise SystemExit('FIX_V5_STOP failed to modify encoder')
    # Small source backup, intentionally placed among transient AI runtime files.
    backup = ROOT / 'ai' / 'runtime' / 'ai_v5_semantic_encoder_before_numeric_fix.gd.txt'
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        backup.write_text(code, encoding='utf-8')
    TARGET.write_text(new, encoding='utf-8')
    print('FIX_V5_NUMERIC_SELECTION_APPLIED v5_encoder_only=1 v4_unchanged=1 checkpoints_unchanged=1')
    for n in (0, 3):
        def bucket(s: str) -> int:
            return int.from_bytes(hashlib.blake2b(s.encode(), digest_size=8).digest(), 'big') % 96
        print(f'  selection:{n} bucket={bucket(f"selection:{n}")} previously_mismatched_float_bucket={bucket(f"selection:{n}.0")}')
    print('NEXT run_v5_score_diagnostic.ps1 (must report mismatch_cases=0); then -PrepareOnly')


if __name__ == '__main__':
    main()
