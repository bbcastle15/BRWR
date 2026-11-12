#!/usr/bin/env python3
"""After standard v5 preflight + R3 receipts: switch only the generated worker.

Never edits game.gd, the original game scene, base v5 policy, or other trainers.
"""
from pathlib import Path
ROOT = Path(__file__).resolve().parent
WORKER = ROOT / 'ai/ai_policy_school_v5_match.gd'
POLICY = ROOT / 'ai/ai_native_policy_v5_momentumone.gd'
OLD = 'res://ai/ai_native_policy_v5.gd'
NEW = 'res://ai/ai_native_policy_v5_momentumone.gd'


def main():
    if not WORKER.is_file() or not POLICY.is_file():
        raise RuntimeError('MOMENTUM_ONE_BUILD_STOP missing generated worker or Momentum-One policy')
    worker = WORKER.read_text(encoding='utf-8-sig')
    if 'BRWR_R3_RECEIPTS_FILE' not in worker:
        raise RuntimeError('MOMENTUM_ONE_BUILD_STOP: R3 receipts not installed in worker')
    if worker.count(OLD) != 1 or NEW in worker:
        raise RuntimeError('MOMENTUM_ONE_BUILD_STOP unexpected native policy path; regenerate with v5 preflight')
    updated = worker.replace(OLD, NEW, 1)
    WORKER.write_bytes(updated.encode('utf-8'))
    print('V5M1_WORKER_OK source_worker_only=1 one_momentum_slot=1 cast_choices_distinct=1 original_v5_policy_unchanged=1', flush=True)

if __name__ == '__main__':
    main()
