#!/usr/bin/env python3
"""BRWR v5-MOMENTUM-ONE RESET: zero-history network + one Momentum slot.

Starts FROM SCRATCH: no R3 or R3-M weights/Adam/baseline are inherited.
Retains the R3 terminal rewards and local cast/reaction/Momentum shaping.


Usage: python ai/python/train_v5_momentumone_reset.py --prepare-only
       python ai/python/train_v5_momentumone_reset.py --godot C:\\...\\Godot_console.exe --games 1

Never overwrites v4/v5/R2/R3 checkpoints, their histories, or the actual Game.
Requires the existing v5 optimized training setup; do not run concurrently
with any other native/Godot trainer (they share generated native JSON/worker).
"""
from __future__ import annotations

import argparse
import csv
import copy
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import torch
from torch import nn

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'ai/python'))
import train_optimized_v5 as parent_v5
import train_optimized_native as native_v4
import v5_encoder
import v5_experiment
import v5_reward_v3 as rew
import v5m1_effect_receipts as receipts
import v5_r3_momentum as mom
import v5_momentum_one as mo

OUTPUT = ROOT / 'ai/model/brwr_policy_v5_momentumone_reset.pt'
HISTORY = ROOT / 'ai/model/training_history_v5_momentumone_reset.csv'
LOCK = ROOT / 'ai/model/v5_momentumone_reset_training.lock'
SOURCE_LOCK = ROOT / 'ai/model/optimized_training_v5.lock'
V4_SOURCE_LOCK = ROOT / 'ai/model/optimized_training.lock'
R1_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v1_training.lock'
R2_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v2_training.lock'
EXPERIMENT = 'v5_momentumone_reset_random_v1'
REWARD_VERSION = rew.REWARD_VERSION + '__' + mom.VERSION + '__' + mo.VERSION
R3_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v3_training.lock'
R3M_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v3_momentum_training.lock'
OLD_GROUP_LOCK = ROOT / 'ai/model/v5_groupbalanced_reset_training.lock'
RESET_SEED = 20261112
HISTORY_COLUMNS = [
    'v5m1_game', 'seed', 'bots', 'avatar', 'difficulty', 'round', 'decisions',
    'winner', 'rose_score', 'best_mage_score', 'mean_mage_score',
    'best_margin_vs_rose', 'rewards', 'rose_reward_mean', 'peer_reward_mean',
    'baseline', 'baseline_source',
    'advantage_abs_mean', 'advantages_clipped', 'updated_weights',
    'loss', 'random_reset_seed', 'points_reward_mean',
    'effective_spell_resolutions', 'effective_reactions', 'uncredited_effects',
    'effect_bonus_total', 'effect_bonus_decisions',
    'momentum_actions', 'momentum_with_cast_alternative', 'momentum_penalty_total'
]


def lock_guard():
    blockers = [p for p in (SOURCE_LOCK, V4_SOURCE_LOCK, R1_SOURCE_LOCK, R2_SOURCE_LOCK, R3_SOURCE_LOCK, R3M_SOURCE_LOCK, OLD_GROUP_LOCK, LOCK) if p.exists()]
    if blockers:
        raise RuntimeError('TRAINER_LOCK_PRESENT: ' + ', '.join(str(x) for x in blockers) +
                           '; finish any other training first. Never delete a live lock.')


def load_checkpoint_state():
    if OUTPUT.exists():
        checkpoint = torch.load(OUTPUT, map_location='cpu', weights_only=False)
        if checkpoint.get('experiment') != EXPERIMENT or checkpoint.get('reward_version') != REWARD_VERSION:
            raise RuntimeError('Incompatible Momentum-One reset checkpoint')
        if checkpoint.get('model_reset') != 'random' or checkpoint.get('random_reset_seed') != RESET_SEED:
            raise RuntimeError('Not the expected genuinely reset random model')
        if checkpoint.get('group_policy_version') != mo.VERSION:
            raise RuntimeError('Wrong candidate sampling policy')
        if checkpoint.get('momentum_penalty') != mom.PENALTY:
            raise RuntimeError('Momentum coefficient mismatch')
        if checkpoint.get('baseline_version') != rew.BASELINE_VERSION:
            raise RuntimeError('Wrong baseline version')
        if int(checkpoint.get('feature_dim', -1)) != v5_encoder.FEATURE_DIM or checkpoint.get('encoder_version') != v5_encoder.ENCODER_VERSION:
            raise RuntimeError('Wrong feature encoder')
    else:
        # No previous model weights, no previous optimizer state, no old baseline.
        # This is a deterministic PyTorch initialization, not warm-start.
        torch.manual_seed(RESET_SEED)
        model = v5_experiment.V5Policy()
        optimizer = torch.optim.Adam(model.parameters(), lr=0.0005)
        checkpoint = {
            'experiment': EXPERIMENT, 'reward_version': REWARD_VERSION,
            'baseline_version': rew.BASELINE_VERSION,
            'group_policy_version': mo.VERSION,
            'momentum_penalty': mom.PENALTY,
            'model_reset': 'random', 'random_reset_seed': RESET_SEED,
            'model': model.state_dict(), 'optimizer': optimizer.state_dict(),
            'games_completed': 0, 'feature_dim': v5_encoder.FEATURE_DIM,
            'encoder_version': v5_encoder.ENCODER_VERSION,
            'baseline_state': rew.new_baseline_state(),
            'last_history_row': None,
            'created': datetime.now().isoformat(timespec='seconds'),
        }
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        save_atomic(checkpoint)
        print('V5M1_RESET_CREATED weights=random optimizer=fresh baseline=empty games=0 random_seed=%d previous_models_unchanged=1' % RESET_SEED, flush=True)
    rew.validate_baseline_state(checkpoint['baseline_state'])
    model = v5_experiment.V5Policy()
    model.load_state_dict(checkpoint['model'])
    optimizer = torch.optim.Adam(model.parameters(), lr=0.0005)
    optimizer.load_state_dict(checkpoint['optimizer'])
    return checkpoint, model, optimizer


def save_atomic(payload: dict):
    tmp = OUTPUT.with_name(OUTPUT.name + '.temporary')
    torch.save(payload, tmp)
    os.replace(tmp, OUTPUT)


def history_rows():
    if not HISTORY.exists():
        return []
    with HISTORY.open('r', encoding='utf-8', newline='') as fh:
        rows = list(csv.reader(fh))
    if not rows or rows[0] != HISTORY_COLUMNS:
        raise RuntimeError('v5-MOMENTUM-ONE training history has unexpected columns')
    return rows[1:]


def append_history(row: list):
    if not HISTORY.exists():
        with HISTORY.open('w', encoding='utf-8', newline='') as fh:
            csv.writer(fh).writerow(HISTORY_COLUMNS)
    with HISTORY.open('a', encoding='utf-8', newline='') as fh:
        csv.writer(fh).writerow(row)


def reconcile_history(checkpoint: dict) -> None:
    """Recover a history row if process stopped between atomic checkpoint and append."""
    done = int(checkpoint['games_completed'])
    rows = history_rows()
    last = int(rows[-1][0]) if rows else 0
    if last == done:
        if len(rows) != done:
            raise RuntimeError('v5-MOMENTUM-ONE history count mismatch')
        return
    if last == done - 1 and len(rows) == last:
        pending = checkpoint.get('last_history_row')
        if not isinstance(pending, list) or int(pending[0]) != done or len(pending) != len(HISTORY_COLUMNS):
            raise RuntimeError('History is one row behind but no recoverable checkpoint row')
        append_history(pending)
        print('V5M1_HISTORY_RECOVERED game=%d from_checkpoint=1' % done, flush=True)
        return
    raise RuntimeError('V5-MOMENTUMONE history/checkpoint mismatch; stop before modifying')


def update_model(model, optimizer, experiences, transitions, advantages,
                 entropy_coef, effect_bonuses, momentum_penalties):
    if not experiences or len(experiences) != len(transitions):
        raise RuntimeError('Experiences and transition records mismatch')
    losses = []
    for step, (transition, record) in enumerate(zip(experiences, transitions), 1):
        idx = transition.player_index
        if not 0 <= idx < len(advantages) or record.get('player_index') != idx:
            raise RuntimeError('Experience/transition player index mismatch')
        if record.get('step') != step or record.get('selected_candidate_id') != transition.selected:
            raise RuntimeError('Experience/transition selected action mismatch')
        options = record.get('legal_candidates')
        request_type = record.get('request_type', '')
        logits = model(transition.candidate_features)
        # CRITICAL: identical hierarchical probability to the Godot policy.
        log_probs = mo.log_probabilities(logits, options, request_type)
        ent = mo.entropy(log_probs, options, request_type)
        a = advantages[idx] + effect_bonuses.get(step, 0.0) + momentum_penalties.get(step, 0.0)
        losses.append(-a * log_probs[transition.selected] - entropy_coef * ent)
    loss = torch.stack(losses).mean()
    if not torch.isfinite(loss):
        raise RuntimeError('Nonfinite Momentum-One policy loss')
    optimizer.zero_grad()
    loss.backward()
    nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
    optimizer.step()
    return float(loss.detach())


def validate_setup_read_only():
    files = [ROOT / 'ai/python/train_optimized_v5.py',
             ROOT / 'ai/python/v5_encoder.py', ROOT / 'ai/python/v5_experiment.py',
             ROOT / 'ai/python/train_optimized_native.py', ROOT / 'ai/python/train.py',
             ROOT / 'ai/python/v5_reward_v3.py', ROOT / 'ai/python/v5_r3_effect_receipts.py',
             ROOT / 'ai/python/v5_r3_momentum.py', ROOT / 'ai/python/v5_momentum_one.py',
             ROOT / 'ai/ai_native_policy_v5_momentumone.gd',
             ROOT / 'ai/ai_momentumone_validation.gd',
             ROOT / 'generate_v5_momentumone_probe.py',
             ROOT / 'build_v5_momentumone_worker.py',
             ROOT / 'build_v5_r3_effect_receipts.py', ROOT / 'r3_game_effect_methods.gd.inc',
             ROOT / 'build_v5m1_roomcast_provenance.py', ROOT / 'ai/python/v5m1_effect_receipts.py']
    for file in files:
        if not file.is_file():
            raise RuntimeError('Required source file missing: ' + str(file))
    print('V5M1_PREPARE_OK tests=pass writes=0 games=0 model_reset_pending=1 old_checkpoints_untouched=1', flush=True)


def prepare_only():
    validate_setup_read_only()


def run(args):
    if args.prepare_only:
        prepare_only()
        return
    if args.games < 1 or args.timeout < 30:
        raise RuntimeError('Games >=1 and timeout >=30 required')
    if not Path(args.godot).is_file():
        raise RuntimeError('Godot executable missing: ' + args.godot)
    lock_guard()
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as fh:
            fh.write('pid=%d\n' % os.getpid())
        state, model, optimizer = load_checkpoint_state()
        reconcile_history(state)
        done = int(state['games_completed'])
        backup_dir = OUTPUT.parent / 'backups'
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / ('brwr_policy_v5_momentumone_reset_before_games%d_%s.pt' %
                               (done, datetime.now().strftime('%Y%m%d_%H%M%S')))
        shutil.copy2(OUTPUT, backup)
        print('V5M1_RESUME_OK games=%d reset_seed=%d backup=%s' %
              (done, state['random_reset_seed'], backup), flush=True)
        # This regenerates the SAME validated v5 optimized worker and writes
        # the native v5 weight JSON. Do not call while original v5 trainer runs.
        parent_v5.preflight(args.godot, model, done)
        native_v4.command([sys.executable, str(ROOT / 'build_v5_r3_effect_receipts.py')], label='Build AI-only R3 effective spell receipts')
        native_v4.command([sys.executable, str(ROOT / 'build_v5m1_roomcast_provenance.py')], label='Trace rebuilt-Room free casts to their triggering Action')
        native_v4.command([sys.executable, str(ROOT / 'build_v5_momentumone_worker.py')], label='Switch generated worker to Momentum-One policy')
        native_v4.command([sys.executable, str(ROOT / 'generate_v5_momentumone_probe.py')], label='Build Python Momentum-One probability probe')
        parity_output = native_v4.command([args.godot, '--headless', '--path', str(ROOT), '--script',
                            'res://ai/ai_momentumone_validation.gd'],
                            label='Full Godot/Python sampling probability parity', timeout=120)
        if 'MOMENTUM_ONE_PARITY' not in parity_output or 'mismatches=0' not in parity_output:
            raise RuntimeError('Momentum-One sampling probability parity failed')
        native_v4.command([args.godot, '--headless', '--path', str(ROOT), '--check-only',
                           '--script', 'res://ai/ai_policy_school_v5_match.gd'],
                          label='Validate R3 worker syntax', timeout=120)
        native_v4.command([args.godot, '--headless', '--path', str(ROOT), '--check-only',
                           '--script', 'res://ai/game_school_cached.gd'],
                          label='Validate R3 cached Game syntax', timeout=120)
        print('V5M1_FAST_SETUP_OK original_game_unchanged=1 random_reset_model=1 separate_checkpoint=1', flush=True)
        baseline_state = copy.deepcopy(state['baseline_state'])
        for offset, (bots, avatar, difficulty) in enumerate(
                native_v4.advance_scenario(args.seed, done, args.games, False)):
            game_no = done + offset + 1
            match_seed = args.seed + game_no
            parent_v5.export_v5(model, game_no - 1)
            print('V5M1_GAME_START %d seed=%d bots=%d avatar=%s/%s' %
                  (game_no, match_seed, bots, avatar, difficulty), flush=True)
            end, exp, episode, log, seconds = parent_v5.run_episode(
                args.godot, match_seed, bots, avatar, difficulty, args.timeout)
            # The R3 AI-only Game writes a receipt for each spell whose actual
            # effects changed authoritative state, including delayed traps.
            # Reject missing, mismatched, or misattributed receipts; NEVER
            # infer success from a chosen cast or effect_resolved event.
            transitions = []
            with episode.open('r', encoding='utf-8') as ef:
                for line in ef:
                    record = json.loads(line)
                    if record.get('record_type') == 'transition':
                        transitions.append(record)
            receipt_path = Path(str(episode) + '.r3_receipts.json')
            effect_bonuses, effect_stats = receipts.load_effect_bonuses(
                receipt_path, seed=match_seed, decisions=len(exp),
                transitions=transitions, bots=bots)
            print('V5M1_EFFECT_RECEIPTS game=%d spells=%d reactions=%d bonuses=%.4f attributed_actions=%d uncredited=%d' %
                  (game_no, effect_stats['effective_spells'], effect_stats['effective_reactions'],
                   effect_stats['bonus_sum'], effect_stats['credited_decisions'], effect_stats['uncredited']), flush=True)
            print('V5M1_ROOMCAST_PROVENANCE game=%d confirmed=%d' % (game_no, effect_stats['room_auto_casts']), flush=True)
            print('V5M1_REACTION_SELECTION_PROVENANCE game=%d confirmed=%d' % (game_no, effect_stats['reaction_card_selections']), flush=True)
            momentum_penalties, momentum_stats = mom.selected_momentum_penalties(transitions, bots)
            if len(transitions) != len(exp):
                raise RuntimeError('Transition/experience count mismatch; cannot apply local penalties')
            print('V5M1_MOMENTUM game=%d count=%d with_cast_option=%d action_steps=%d local_penalty_total=%.4f' %
                  (game_no, momentum_stats['momentum_actions'], momentum_stats['with_cast_alternative'],
                   momentum_stats['action_decisions'], momentum_stats['total_penalty']), flush=True)
            group_stats = mo.summaries(transitions)
            print('V5M1_ACTIONS game=%d action_steps=%d selected=%s available_candidates=%s virtual_slots=%s both=%d cast_when_both=%d momentum_when_both=%d' %
                  (game_no, group_stats['action_steps'], json.dumps(group_stats['selected'], sort_keys=True),
                   json.dumps(group_stats['candidate_totals'], sort_keys=True),
                   json.dumps(group_stats['virtual_slots'], sort_keys=True),
                   group_stats['steps_with_cast_and_momentum'], group_stats['cast_when_both'],
                   group_stats['momentum_when_both']), flush=True)
            # Full real-episode expected probability audit BEFORE weight updates.
            audit = mo.audit_probabilities(model, exp, transitions)
            print('V5M1_REAL_PROBS game=%d both=%d mean_p_momentum=%.5f mean_p_cast=%.5f momentum_selected=%d cast_selected=%d' %
                  (game_no, audit['steps_both'], audit['mean_momentum_probability'],
                   audit['mean_cast_probability'], audit['momentum_selected'],
                   audit['cast_selected']), flush=True)
            rewards, metrics = rew.rose_peer_rewards(end, bots)
            rose_component_mean = sum(x['rose_reward'] for x in metrics['components']) / bots
            peer_component_mean = sum(x['peer_reward'] for x in metrics['components']) / bots
            points_component_mean = sum(x['personal_points_reward'] for x in metrics['components']) / bots
            key = rew.scenario_key(bots, avatar, difficulty)
            baseline, source = rew.predict_baseline(baseline_state, key)
            advantages, raw_adv, clipped = rew.compute_advantages(rewards, baseline)
            if baseline is None:
                loss, updated = 0.0, False
                print('V5M1_CALIBRATION_ONLY game=%d no_gradient=1 historical_baseline_missing=1' % game_no, flush=True)
            else:
                loss = update_model(model, optimizer, exp, transitions, advantages, args.entropy, effect_bonuses, momentum_penalties)
                updated = True
            # Update historical baseline strictly AFTER gradient computation.
            rew.observe_completed_episode(baseline_state, key, rewards)
            adv_mean = sum(abs(x) for x in raw_adv) / len(raw_adv) if raw_adv else 0.0
            record = [game_no, match_seed, bots, avatar, difficulty,
                      end.get('round', ''), len(exp), metrics['winner'],
                      metrics['rose_score'], metrics['best_mage_score'],
                      round(metrics['mean_mage_score'], 4),
                      metrics['best_margin_vs_rose'],
                      json.dumps([round(x, 6) for x in rewards]),
                      round(rose_component_mean, 6), round(peer_component_mean, 6),
                      '' if baseline is None else round(baseline, 6), source,
                      round(adv_mean, 6), clipped, int(updated), round(loss, 6),
                      state['random_reset_seed'], round(points_component_mean, 6),
                      effect_stats['effective_spells'], effect_stats['effective_reactions'],
                      effect_stats['uncredited'], round(effect_stats['bonus_sum'], 6),
                      effect_stats['credited_decisions'], momentum_stats['momentum_actions'],
                      momentum_stats['with_cast_alternative'], round(momentum_stats['total_penalty'], 6)]
            # Single atomic checkpoint persists BOTH model and baseline state.
            current = dict(state)
            current.update({'model': model.state_dict(),
                            'optimizer': optimizer.state_dict(),
                            'baseline_state': copy.deepcopy(baseline_state),
                            'games_completed': game_no,
                            'last_history_row': record})
            save_atomic(current)
            parent_v5.export_v5(model, game_no)
            append_history(record)
            print('V5M1_GAME_SAVED %d decisions=%d seconds=%.2f winner=%d rose_score=%.1f best_mage=%.1f best_margin=%.1f baseline=%s reward_mean=%.4f points_term=%.4f rose_term=%.4f peer_term=%.4f mean_abs_adv=%.4f spells=%d reactions=%d effect_bonus=%.4f momentum=%d momentum_penalty=%.4f updated=%d loss=%.5f checkpoint_games=%d' %
                  (game_no, len(exp), seconds, metrics['winner'],
                   metrics['rose_score'], metrics['best_mage_score'],
                   metrics['best_margin_vs_rose'],
                   'cold' if baseline is None else '%.4f' % baseline,
                   sum(rewards) / len(rewards), points_component_mean, rose_component_mean, peer_component_mean,
                   adv_mean, effect_stats['effective_spells'], effect_stats['effective_reactions'],
                   effect_stats['bonus_sum'], momentum_stats['momentum_actions'],
                   momentum_stats['total_penalty'], int(updated), loss, game_no), flush=True)
            if args.keep_episodes:
                print('V5M1_EPISODE_FILE ' + str(episode), flush=True)
                print('V5M1_RECEIPTS_FILE ' + str(receipt_path), flush=True)
            if not args.keep_episodes:
                rel = episode.relative_to(ROOT).as_posix()
                tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '--', rel],
                                         cwd=ROOT, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL) if shutil.which('git') else None
                if tracked is not None and tracked.returncode != 0:
                    episode.unlink(missing_ok=True)
                    receipt_path.unlink(missing_ok=True)
                    print('  V5M1_EPISODE_AND_RECEIPTS_CLEANED after_checkpoint=1', flush=True)
                else:
                    print('  V5M1_EPISODE_JSONL_RETAINED', flush=True)
            state = current
        print('V5M1_TRAIN_COMPLETE from=%d to=%d previous_models_unchanged=1' %
              (done, done + args.games), flush=True)
    finally:
        LOCK.unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--godot', default='')
    ap.add_argument('--games', type=int, default=1)
    ap.add_argument('--seed', type=int, default=20350101)
    ap.add_argument('--timeout', type=int, default=300)
    ap.add_argument('--entropy', type=float, default=0.02)
    ap.add_argument('--prepare-only', action='store_true')
    ap.add_argument('--keep-episodes', action='store_true')
    args = ap.parse_args()
    run(args)


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as exc:
        print('V5M1_TRAIN_STOP %s: %s' % (type(exc).__name__, exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
