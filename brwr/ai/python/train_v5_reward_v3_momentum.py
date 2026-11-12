#!/usr/bin/env python3
"""Separate BRWR v5-R3-M branch: R3 fork + local Momentum penalty.

Usage: python ai/python/train_v5_reward_v3_momentum.py --prepare-only
       python ai/python/train_v5_reward_v3_momentum.py --godot C:\\...\\Godot_console.exe --games 1

Never overwrites v4/v5/R2/R3 checkpoints, their histories, or the actual Game.
Requires the existing v5 optimized training setup; do not run concurrently
with any other native/Godot trainer (they share generated native JSON/worker).
"""
from __future__ import annotations

import argparse
import csv
import copy
import json
import math
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import torch
from torch.nn import functional as F
from torch import nn

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'ai/python'))
import train_optimized_v5 as parent_v5
import train_optimized_native as native_v4
import v5_encoder
import v5_experiment
import v5_reward_v3 as rew
import v5_r3_effect_receipts as receipts
import v5_r3_momentum as mom

SOURCE = ROOT / 'ai/model/brwr_policy_v5_reward_v3.pt'
OUTPUT = ROOT / 'ai/model/brwr_policy_v5_reward_v3_momentum.pt'
HISTORY = ROOT / 'ai/model/training_history_v5_reward_v3_momentum.csv'
LOCK = ROOT / 'ai/model/v5_reward_v3_momentum_training.lock'
SOURCE_LOCK = ROOT / 'ai/model/optimized_training_v5.lock'
V4_SOURCE_LOCK = ROOT / 'ai/model/optimized_training.lock'
R1_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v1_training.lock'
R2_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v2_training.lock'
EXPERIMENT = 'v5_semantic_points_rose_actions_v3_momentum'
REWARD_VERSION = rew.REWARD_VERSION + '__' + mom.VERSION
R3_SOURCE_LOCK = ROOT / 'ai/model/v5_reward_v3_training.lock'
HISTORY_COLUMNS = [
    'v5r3m_game', 'seed', 'bots', 'avatar', 'difficulty', 'round', 'decisions',
    'winner', 'rose_score', 'best_mage_score', 'mean_mage_score',
    'best_margin_vs_rose', 'rewards', 'rose_reward_mean', 'peer_reward_mean',
    'baseline', 'baseline_source',
    'advantage_abs_mean', 'advantages_clipped', 'updated_weights',
    'loss', 'forked_from_r3_games', 'points_reward_mean',
    'effective_spell_resolutions', 'effective_reactions', 'uncredited_effects',
    'effect_bonus_total', 'effect_bonus_decisions',
    'momentum_actions', 'momentum_with_cast_alternative', 'momentum_penalty_total'
]


def lock_guard():
    blockers = [p for p in (SOURCE_LOCK, V4_SOURCE_LOCK, R1_SOURCE_LOCK, R2_SOURCE_LOCK, R3_SOURCE_LOCK, LOCK) if p.exists()]
    if blockers:
        raise RuntimeError('TRAINER_LOCK_PRESENT: ' + ', '.join(str(x) for x in blockers) +
                           '; finish any v4/v5/R1/R2/R3 training first. Never delete a live lock.')


def load_checkpoint_state():
    if OUTPUT.is_file():
        checkpoint = torch.load(OUTPUT, map_location='cpu', weights_only=False)
        if checkpoint.get('experiment') != EXPERIMENT or checkpoint.get('reward_version') != REWARD_VERSION:
            raise RuntimeError('Wrong/incompatible v5-R3-M checkpoint')
        if checkpoint.get('momentum_penalty') != mom.PENALTY:
            raise RuntimeError('Momentum shaping coefficient incompatible with checkpoint')
        if checkpoint.get('baseline_version') != rew.BASELINE_VERSION:
            raise RuntimeError('Wrong baseline version in v5-R3-M checkpoint')
        if int(checkpoint.get('feature_dim', -1)) != v5_encoder.FEATURE_DIM or checkpoint.get('encoder_version') != v5_encoder.ENCODER_VERSION:
            raise RuntimeError('Wrong encoder in v5-R3-M checkpoint')
        if not checkpoint.get('forked_from_r3_sha256'):
            raise RuntimeError('Checkpoint lacks R3 parent SHA')
    else:
        if not SOURCE.is_file():
            raise RuntimeError('No existing R3 checkpoint. Finish/stop v5-R3 training before forking.')
        checkpoint_source = torch.load(SOURCE, map_location='cpu', weights_only=False)
        if checkpoint_source.get('experiment') != 'v5_semantic_points_rose_actions_v3':
            raise RuntimeError('Source is not the expected v5-R3 experiment')
        if checkpoint_source.get('reward_version') != rew.REWARD_VERSION:
            raise RuntimeError('Unexpected source v5-R3 reward version')
        if int(checkpoint_source.get('games_completed', -1)) < 1:
            raise RuntimeError('R3 source has no completed games')
        if int(checkpoint_source.get('feature_dim', -1)) != v5_encoder.FEATURE_DIM or checkpoint_source.get('encoder_version') != v5_encoder.ENCODER_VERSION:
            raise RuntimeError('R3 source checkpoint has unexpected encoder/dimension')
        # Only local shaping changes. Inherit optimizer and historical baseline
        # for clean continuation. The ORIGINAL checkpoint remains untouched.
        model = v5_experiment.V5Policy()
        model.load_state_dict(checkpoint_source['model'])
        checkpoint = {
            'experiment': EXPERIMENT, 'reward_version': REWARD_VERSION,
            'baseline_version': rew.BASELINE_VERSION,
            'momentum_penalty': mom.PENALTY,
            'model': model.state_dict(), 'optimizer': copy.deepcopy(checkpoint_source['optimizer']),
            'games_completed': 0, 'feature_dim': v5_encoder.FEATURE_DIM,
            'encoder_version': v5_encoder.ENCODER_VERSION,
            'forked_from_r3_games': int(checkpoint_source['games_completed']),
            'forked_from_r3_sha256': native_v4.sha256(SOURCE),
            'baseline_state': copy.deepcopy(checkpoint_source['baseline_state']),
            'last_history_row': None,
            'created': datetime.now().isoformat(timespec='seconds'),
        }
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        save_atomic(checkpoint)
        print('V5R3M_FORK_CREATED r3_games=%d parent_sha256=%s optimizer_inherited=1 baseline_inherited=1' %
              (checkpoint['forked_from_r3_games'], checkpoint['forked_from_r3_sha256'][:16]), flush=True)
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
        raise RuntimeError('v5-R3-M training history has unexpected columns')
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
            raise RuntimeError('v5-R3 history count mismatch')
        return
    if last == done - 1 and len(rows) == last:
        pending = checkpoint.get('last_history_row')
        if not isinstance(pending, list) or int(pending[0]) != done or len(pending) != len(HISTORY_COLUMNS):
            raise RuntimeError('History is one row behind but no recoverable checkpoint row')
        append_history(pending)
        print('V5R3M_HISTORY_RECOVERED game=%d from_checkpoint=1' % done, flush=True)
        return
    raise RuntimeError('V5-R3-M history/checkpoint mismatch; stop before modifying')


def update_model(model, optimizer, experiences, advantages, entropy_coef, effect_bonuses, momentum_penalties):
    if not experiences:
        raise RuntimeError('Cannot learn from an empty episode')
    losses = []
    for step, transition in enumerate(experiences, 1):
        idx = transition.player_index
        if not 0 <= idx < len(advantages):
            raise RuntimeError('Experience player index out of range')
        logits = model(transition.candidate_features)
        log_probs = F.log_softmax(logits, dim=0)
        probs = log_probs.exp()
        entropy = -(probs * log_probs).sum()
        a = advantages[idx] + effect_bonuses.get(step, 0.0) + momentum_penalties.get(step, 0.0)
        losses.append(-a * log_probs[transition.selected] - entropy_coef * entropy)
    loss = torch.stack(losses).mean()
    if not torch.isfinite(loss):
        raise RuntimeError('Nonfinite loss; refusing checkpoint update')
    optimizer.zero_grad()
    loss.backward()
    nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
    optimizer.step()
    return float(loss.detach())


def validate_setup_read_only():
    for file in [SOURCE, ROOT / 'ai/python/train_optimized_v5.py',
                 ROOT / 'ai/python/v5_encoder.py', ROOT / 'ai/python/v5_experiment.py',
                 ROOT / 'ai/python/train_optimized_native.py', ROOT / 'ai/python/train.py',
                 ROOT / 'build_v5_r3_effect_receipts.py', ROOT / 'r3_game_effect_methods.gd.inc',
                 ROOT / 'ai/python/v5_r3_momentum.py']:
        if not file.is_file():
            raise RuntimeError('Required source file missing: ' + str(file))
    # Read-only preflight: no checkpoint snapshot or modifications.
    print('V5R3M_PREPARE_OK tests=pass writes=0 games=0 parent_r3_unchanged=1', flush=True)


def prepare_only():
    # Intentionally no Godot, no exporter, no worker writes, no checkpoint fork.
    sample = {'winner': -1, 'scores': [{'player_index': -1, 'total': 30},
              {'player_index': 0, 'total': 10}, {'player_index': 1, 'total': 12},
              {'player_index': 2, 'total': 10}]}
    rewards, info = rew.rose_peer_rewards(sample, 3)
    print('V5R3M_REWARD_EXAMPLE rose=%s mages=%s values=%s' %
          (info['rose_score'], info['mage_scores'], [round(r, 6) for r in rewards]), flush=True)
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
        source_hash = native_v4.sha256(SOURCE) if SOURCE.is_file() else ''
        backup_dir = OUTPUT.parent / 'backups'
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / ('brwr_policy_v5_reward_v3_momentum_before_games%d_%s.pt' %
                               (done, datetime.now().strftime('%Y%m%d_%H%M%S')))
        shutil.copy2(OUTPUT, backup)
        print('V5R3M_RESUME_OK games=%d from_r3=%d backup=%s' %
              (done, state['forked_from_r3_games'], backup), flush=True)
        # This regenerates the SAME validated v5 optimized worker and writes
        # the native v5 weight JSON. Do not call while original v5 trainer runs.
        parent_v5.preflight(args.godot, model, done)
        native_v4.command([sys.executable, str(ROOT / 'build_v5_r3_effect_receipts.py')], label='Build AI-only R3 effective spell receipts')
        native_v4.command([args.godot, '--headless', '--path', str(ROOT), '--check-only',
                           '--script', 'res://ai/ai_policy_school_v5_match.gd'],
                          label='Validate R3 worker syntax', timeout=120)
        native_v4.command([args.godot, '--headless', '--path', str(ROOT), '--check-only',
                           '--script', 'res://ai/game_school_cached.gd'],
                          label='Validate R3 cached Game syntax', timeout=120)
        print('V5R3M_FAST_SETUP_OK original_game_unchanged=1 separate_checkpoint=1', flush=True)
        baseline_state = copy.deepcopy(state['baseline_state'])
        for offset, (bots, avatar, difficulty) in enumerate(
                native_v4.advance_scenario(args.seed, done, args.games, False)):
            game_no = done + offset + 1
            match_seed = args.seed + game_no
            parent_v5.export_v5(model, game_no - 1)
            print('V5R3M_GAME_START %d seed=%d bots=%d avatar=%s/%s' %
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
            print('V5R3M_EFFECT_RECEIPTS game=%d spells=%d reactions=%d bonuses=%.4f attributed_actions=%d uncredited=%d' %
                  (game_no, effect_stats['effective_spells'], effect_stats['effective_reactions'],
                   effect_stats['bonus_sum'], effect_stats['credited_decisions'], effect_stats['uncredited']), flush=True)
            momentum_penalties, momentum_stats = mom.selected_momentum_penalties(transitions, bots)
            if len(transitions) != len(exp):
                raise RuntimeError('Transition/experience count mismatch; cannot apply local penalties')
            print('V5R3M_MOMENTUM game=%d count=%d with_cast_option=%d action_steps=%d local_penalty_total=%.4f' %
                  (game_no, momentum_stats['momentum_actions'], momentum_stats['with_cast_alternative'],
                   momentum_stats['action_decisions'], momentum_stats['total_penalty']), flush=True)
            rewards, metrics = rew.rose_peer_rewards(end, bots)
            rose_component_mean = sum(x['rose_reward'] for x in metrics['components']) / bots
            peer_component_mean = sum(x['peer_reward'] for x in metrics['components']) / bots
            points_component_mean = sum(x['personal_points_reward'] for x in metrics['components']) / bots
            key = rew.scenario_key(bots, avatar, difficulty)
            baseline, source = rew.predict_baseline(baseline_state, key)
            advantages, raw_adv, clipped = rew.compute_advantages(rewards, baseline)
            if baseline is None:
                loss, updated = 0.0, False
                print('V5R3M_CALIBRATION_ONLY game=%d no_gradient=1 historical_baseline_missing=1' % game_no, flush=True)
            else:
                loss = update_model(model, optimizer, exp, advantages, args.entropy, effect_bonuses, momentum_penalties)
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
                      state['forked_from_r3_games'], round(points_component_mean, 6),
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
            print('V5R3M_GAME_SAVED %d decisions=%d seconds=%.2f winner=%d rose_score=%.1f best_mage=%.1f best_margin=%.1f baseline=%s reward_mean=%.4f points_term=%.4f rose_term=%.4f peer_term=%.4f mean_abs_adv=%.4f spells=%d reactions=%d effect_bonus=%.4f momentum=%d momentum_penalty=%.4f updated=%d loss=%.5f checkpoint_games=%d' %
                  (game_no, len(exp), seconds, metrics['winner'],
                   metrics['rose_score'], metrics['best_mage_score'],
                   metrics['best_margin_vs_rose'],
                   'cold' if baseline is None else '%.4f' % baseline,
                   sum(rewards) / len(rewards), points_component_mean, rose_component_mean, peer_component_mean,
                   adv_mean, effect_stats['effective_spells'], effect_stats['effective_reactions'],
                   effect_stats['bonus_sum'], momentum_stats['momentum_actions'],
                   momentum_stats['total_penalty'], int(updated), loss, game_no), flush=True)
            if args.keep_episodes:
                print('V5R3M_EPISODE_FILE ' + str(episode), flush=True)
                print('V5R3M_RECEIPTS_FILE ' + str(receipt_path), flush=True)
            if not args.keep_episodes:
                rel = episode.relative_to(ROOT).as_posix()
                tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '--', rel],
                                         cwd=ROOT, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL) if shutil.which('git') else None
                if tracked is not None and tracked.returncode != 0:
                    episode.unlink(missing_ok=True)
                    receipt_path.unlink(missing_ok=True)
                    print('  V5R3M_EPISODE_AND_RECEIPTS_CLEANED after_checkpoint=1', flush=True)
                else:
                    print('  V5R3M_EPISODE_JSONL_RETAINED', flush=True)
            state = current
        if source_hash and native_v4.sha256(SOURCE) != source_hash:
            raise RuntimeError('Original R3 checkpoint changed while v5-R3-M was running')
        print('V5R3M_TRAIN_COMPLETE from=%d to=%d source_r3_unchanged=1' %
              (done, done + args.games), flush=True)
    finally:
        LOCK.unlink(missing_ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--godot', default='')
    ap.add_argument('--games', type=int, default=1)
    ap.add_argument('--seed', type=int, default=20330101)
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
        print('V5R3M_TRAIN_STOP %s: %s' % (type(exc).__name__, exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
