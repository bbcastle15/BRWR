#!/usr/bin/env python3
"""BRWR v5 experimental on-policy training, separate from the validated v4.

One FRESH Godot process per episode. Uses exact original v4 reward/REINFORCE
algorithm to isolate the semantic encoder change. New checkpoints, history,
model JSON, worker and datasets are stored under v5-specific filenames.
Requires the prior v4 optimized training and v5 phase-1 encoder installed.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'ai/python'))
import train as v4
import train_optimized_native as native_v4
import v5_encoder
import v5_experiment

V4_CHECKPOINT = ROOT / 'ai/model/brwr_policy_v4.pt'
V5_INIT = ROOT / 'ai/model/brwr_policy_v5_init.pt'
V5_CHECKPOINT = ROOT / 'ai/model/brwr_policy_v5.pt'
V5_JSON = ROOT / 'ai/model/native_policy_v5.json'
V5_HISTORY = ROOT / 'ai/model/training_history_v5.csv'
V5_LOCK = ROOT / 'ai/model/optimized_training_v5.lock'
V5_WORKER = 'res://ai/ai_policy_school_v5_match.gd'
V5_HEADER = ['v5_game', 'seed', 'bots', 'avatar', 'difficulty', 'round', 'decisions',
             'winner', 'rewards', 'loss', 'v4_parent_games']


def check_parent_hash(parent_hash: str) -> None:
    if not V4_CHECKPOINT.is_file():
        raise RuntimeError('Missing original v4 checkpoint')
    current = native_v4.sha256(V4_CHECKPOINT)
    if parent_hash and parent_hash != current:
        raise RuntimeError('v4 parent checkpoint changed since v5 initialization. '
                           'Restore/check the v4 checkpoint before continuing to avoid accidental provenance mismatch')


def load_or_create_v5() -> tuple[dict, v5_experiment.V5Policy, torch.optim.Optimizer, int]:
    if not V4_CHECKPOINT.is_file():
        raise RuntimeError('Missing ai/model/brwr_policy_v4.pt; never fall back to random initialization')
    parent = torch.load(V4_CHECKPOINT, map_location='cpu', weights_only=False)
    if int(parent.get('games_completed', -1)) < 500:
        raise RuntimeError('Expected v4 checkpoint with at least 500 games; found ' + str(parent.get('games_completed')))
    if not V5_CHECKPOINT.is_file():
        if not V5_INIT.is_file():
            v5_experiment.initialize_checkpoint()  # refuses overwrite; tested phase-1 warmstart
        initialized = torch.load(V5_INIT, map_location='cpu', weights_only=False)
        check_parent_hash(str(initialized.get('v4_checkpoint_sha256', '')))
        if int(initialized.get('games_completed', -1)) != 0:
            raise RuntimeError('V5_INIT does not represent an untrained initialization')
        # Atomic checkpoint creation. Never write to v4.
        temp = V5_CHECKPOINT.with_name(V5_CHECKPOINT.name + '.init-tmp')
        shutil.copyfile(V5_INIT, temp)
        os.replace(temp, V5_CHECKPOINT)
        print('V5_CHECKPOINT_CREATED from_v4_games=' + str(parent['games_completed']) + ' v5_games=0', flush=True)
    state = torch.load(V5_CHECKPOINT, map_location='cpu', weights_only=False)
    if int(state.get('feature_dim', -1)) != v5_encoder.FEATURE_DIM or state.get('encoder_version') != v5_encoder.ENCODER_VERSION:
        raise RuntimeError('Wrong v5 checkpoint encoder version/features; refusing to train')
    check_parent_hash(str(state.get('v4_checkpoint_sha256', '')))
    if 'optimizer' not in state:
        raise RuntimeError('v5 checkpoint missing optimizer state')
    model = v5_experiment.V5Policy()
    model.load_state_dict(state['model'])
    optimizer = torch.optim.Adam(model.parameters(), lr=0.0005)
    optimizer.load_state_dict(state['optimizer'])
    completed = int(state.get('games_completed', -1))
    if completed < 0:
        raise RuntimeError('Invalid completed-game counter in v5 checkpoint')
    print('V5_RESUME_OK completed_v5=' + str(completed) +
          ' parent_v4=' + str(state.get('initialized_from_v4_games')) +
          ' feature_dim=' + str(v5_encoder.FEATURE_DIM) +
          ' checkpoint=' + str(V5_CHECKPOINT), flush=True)
    return state, model, optimizer, completed


def export_v5(model: v5_experiment.V5Policy, completed: int) -> None:
    # Keep the v4 categorical token cache, but do not modify the v4 native model.
    base_doc_path = ROOT / 'ai/model/native_policy_v4.json'
    source = json.loads(base_doc_path.read_text(encoding='utf-8')) if base_doc_path.is_file() else {}
    out = {'format': 'BRWR_NATIVE_V5_1', 'feature_dim': v5_encoder.FEATURE_DIM,
           'encoder_version': v5_encoder.ENCODER_VERSION, 'checkpoint_games': completed,
           'token_buckets': source.get('token_buckets', {})}
    for layer, pos in enumerate((0, 2, 4)):
        linear = model.net[pos]
        out['w' + str(layer)] = linear.weight.detach().cpu().reshape(-1).tolist()
        out['b' + str(layer)] = linear.bias.detach().cpu().tolist()
    V5_JSON.parent.mkdir(parents=True, exist_ok=True)
    tmp = V5_JSON.with_name(V5_JSON.name + '.temp')
    tmp.write_text(json.dumps(out, separators=(',', ':'), ensure_ascii=False), encoding='utf-8')
    os.replace(tmp, V5_JSON)


def generate_probe(model: v5_experiment.V5Policy) -> int:
    probe_path = ROOT / 'ai/model/v5_encoder_probe.json'
    if not probe_path.is_file():
        raise RuntimeError('Missing v5 encoder probe; run run_v5_encoder_audit.ps1 first')
    source = json.loads(probe_path.read_text(encoding='utf-8'))
    data = []
    model.eval()
    with torch.no_grad():
        for case in source.get('cases', []):
            observation = case['observation']
            decision = case['decision']
            option = case['option']
            index = int(case['index'])
            total = int(case['total_options'])
            features = v5_encoder.encode_action(observation, decision, option, index, total)
            score = float(model(torch.tensor([features], dtype=torch.float32))[0].item())
            data.append({'observation': observation, 'decision': decision, 'option': option,
                         'index': index, 'total_options': total, 'expected_score': score})
    if len(data) < 12:
        raise RuntimeError('Need >=12 real v5 validation cases')
    path = ROOT / 'ai/model/v5_policy_probe.json'
    path.write_text(json.dumps({'cases': data}, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    return len(data)


def preflight(godot: str, model: v5_experiment.V5Policy, completed: int) -> None:
    # Executes the validated v4 setup, including the already-proven cache and UI guards.
    native_v4.preflight(godot, sys.executable)
    required = [ROOT / 'ai/ai_v5_semantic_encoder.gd', ROOT / 'ai/ai_native_policy_v5.gd',
                ROOT / 'ai/ai_native_policy_v5_validation.gd', ROOT / 'build_v5_worker.py',
                ROOT / 'ai/python/v5_encoder.py', ROOT / 'ai/python/v5_experiment.py',
                ROOT / 'ai/model/v5_encoder_probe.json', ROOT / 'ai/ai_v5_encoder_parity.gd']
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file()]
    if missing:
        raise RuntimeError('Missing v5 phase-1 or phase-2 files: ' + ', '.join(missing))
    v4_sha = native_v4.sha256(V4_CHECKPOINT)
    protected = {name: native_v4.sha256(ROOT / name) for name in
                 ('game.gd', 'game.tscn', 'ai/python/train.py', 'ai/python/train_optimized_native.py')}
    native_v4.command([sys.executable, str(ROOT / 'build_v5_worker.py')], label='Create isolated v5 worker')
    export_v5(model, completed)
    n = generate_probe(model)
    print('V5_POLICY_PROBE_CREATED cases=' + str(n), flush=True)
    output = native_v4.command([godot, '--headless', '--path', str(ROOT), '--script',
                                'res://ai/ai_v5_encoder_parity.gd'], label='V5 encoder parity', timeout=180)
    if 'V5_SEMANTIC_PARITY' not in output or 'mismatches=0' not in output:
        raise RuntimeError('V5 semantic feature parity failed')
    output = native_v4.command([godot, '--headless', '--path', str(ROOT), '--script',
                                'res://ai/ai_native_policy_v5_validation.gd'],
                               label='V5 policy score parity', timeout=180)
    if 'V5_POLICY_PARITY' not in output or 'mismatches=0' not in output:
        raise RuntimeError('V5 policy score parity failed')
    for name, digest in protected.items():
        if native_v4.sha256(ROOT / name) != digest:
            raise RuntimeError('Protected source changed: ' + name)
    if native_v4.sha256(V4_CHECKPOINT) != v4_sha:
        raise RuntimeError('V4 checkpoint changed during v5 preparation')
    print('V5_FAST_SETUP_OK no_rules_changes=1 v4_checkpoint_untouched=1', flush=True)


def parse_episode(path: Path, seed: int, bots: int) -> tuple[dict, list[v4.Experience]]:
    # Same structural validation as the v4 native trainer, with v5 features.
    if not path.is_file() or path.stat().st_size < 50:
        raise RuntimeError('Missing or empty v5 episode: ' + str(path))
    experiences = []
    header = None
    end = None
    n = 0
    with path.open('r', encoding='utf-8') as fh:
        for lineno, line in enumerate(fh, 1):
            if not line.strip():
                continue
            item = json.loads(line)
            typ = item.get('record_type')
            if typ == 'episode_start':
                if header is not None or n:
                    raise RuntimeError('Duplicate episode_start')
                header = item
            elif typ == 'transition':
                if header is None or end is not None:
                    raise RuntimeError('Out-of-order transition')
                n += 1
                if int(item.get('step', -1)) != n or int(item.get('seed', -1)) != seed:
                    raise RuntimeError('Transition step or seed mismatch at line ' + str(lineno))
                player = int(item['player_index'])
                if player < 0 or player >= bots:
                    raise RuntimeError('Invalid player index')
                options = item['legal_candidates']
                selected = int(item['selected_candidate_id'])
                if not isinstance(options, list) or selected < 0 or selected >= len(options):
                    raise RuntimeError('Invalid selected candidate')
                obs = item['observation']
                dec = {'player_index': player, 'type': item.get('request_type', ''),
                       'substep': item.get('substep', ''), 'candidates': options}
                inputs = torch.tensor([v5_encoder.encode_action(obs, dec, c, ix, len(options))
                                       for ix, c in enumerate(options)], dtype=torch.float32)
                if inputs.shape[1] != v5_encoder.FEATURE_DIM:
                    raise RuntimeError('Unexpected encoded dimension in episode')
                experiences.append(v4.Experience(player, inputs, selected))
            elif typ == 'episode_end':
                if header is None or end is not None:
                    raise RuntimeError('Duplicate/invalid episode_end')
                end = item
            else:
                raise RuntimeError('Unexpected episode record type ' + repr(typ))
    if header is None or end is None or n == 0:
        raise RuntimeError('Incomplete v5 episode')
    if int(header.get('seed', -1)) != seed or int(end.get('seed', -1)) != seed:
        raise RuntimeError('Episode seed mismatch')
    if int(header.get('human_player_count', -1)) != bots or int(end.get('human_player_count', -1)) != bots:
        raise RuntimeError('Episode player count mismatch')
    if int(end.get('decisions', -1)) != n:
        raise RuntimeError('Inconsistent episode count')
    return end, experiences


def run_episode(godot: str, seed: int, bots: int, avatar: str, difficulty: str, timeout: int):
    log_dir = ROOT / 'ai/runtime'
    log_dir.mkdir(parents=True, exist_ok=True)
    scenario = 'h%d_av%s_%s_normal' % (bots, avatar, difficulty if avatar != 'none' else 'na')
    path = ROOT / 'ai/datasets' / ('v5_semantic_episode_%d_%s.jsonl' % (seed, scenario))
    if path.exists():
        archive_dir = ROOT / 'ai/datasets/replaced_before_v5_training'
        archive_dir.mkdir(parents=True, exist_ok=True)
        destination = archive_dir / (path.name + '.' + datetime.now().strftime('%Y%m%d_%H%M%S_%f') + '.previous')
        path.replace(destination)
        print('V5_PREVIOUS_EPISODE_ARCHIVED ' + str(destination), flush=True)
    log = log_dir / ('v5_training_seed_%d.log' % seed)
    cmd = [godot, '--headless', '--path', str(ROOT), '--script', V5_WORKER, '--',
           str(seed), str(bots), avatar, difficulty, 'normal']
    start = time.perf_counter()
    with log.open('w', encoding='utf-8', errors='replace') as stream:
        try:
            result = subprocess.run(cmd, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError('V5 Godot exceeded timeout=%d s. Read %s' % (timeout, log)) from exc
    elapsed = time.perf_counter() - start
    output = log.read_text(encoding='utf-8', errors='replace')
    if result.returncode != 0 or 'AI_EPISODE_COMPLETE seed=' not in output:
        raise RuntimeError('Godot V5 failed (code=%d): %s\n%s' %
                           (result.returncode, log, '\n'.join(output.splitlines()[-45:])))
    marker = re.search(r'(?m)^AI_EPISODE_FILE\s+(.+?)\s*$', output)
    if marker is None or Path(marker.group(1).strip()).resolve() != path.resolve():
        raise RuntimeError('Unexpected/missing V5 episode output marker; log=' + str(log))
    end, transitions = parse_episode(path, seed, bots)
    return end, transitions, path, log, elapsed


def save_checkpoint(state: dict, model: v5_experiment.V5Policy,
                    optimizer: torch.optim.Optimizer, game_no: int):
    current = dict(state)
    current.update({'model': model.state_dict(), 'optimizer': optimizer.state_dict(),
                    'games_completed': game_no, 'feature_dim': v5_encoder.FEATURE_DIM,
                    'encoder_version': v5_encoder.ENCODER_VERSION})
    temp = V5_CHECKPOINT.with_name(V5_CHECKPOINT.name + '.training-tmp')
    torch.save(current, temp)
    os.replace(temp, V5_CHECKPOINT)


def validate_history(completed: int) -> None:
    if not V5_HISTORY.is_file():
        if completed:
            raise RuntimeError('v5 checkpoint exists but history is missing; preserve files, investigate before continuing')
        return
    with V5_HISTORY.open('r', encoding='utf-8', newline='') as handle:
        rows = list(csv.reader(handle))
    if not rows or rows[0] != V5_HEADER:
        raise RuntimeError('Invalid v5 history header')
    if rows[1:]:
        latest = int(rows[-1][0])
        if latest != completed:
            raise RuntimeError('v5 history/checkpoint mismatch: history=%d checkpoint=%d' % (latest, completed))
    elif completed:
        raise RuntimeError('v5 checkpoint has episodes but empty history')


def append_history(row: list) -> None:
    if not V5_HISTORY.is_file():
        V5_HISTORY.parent.mkdir(parents=True, exist_ok=True)
        with V5_HISTORY.open('w', encoding='utf-8', newline='') as handle:
            csv.writer(handle).writerow(V5_HEADER)
    with V5_HISTORY.open('a', encoding='utf-8', newline='') as handle:
        csv.writer(handle).writerow(row)


def train() -> None:
    parser = argparse.ArgumentParser(description='BRWR v5 semantic encoder isolated native training')
    parser.add_argument('--godot', required=True)
    parser.add_argument('--games', type=int, default=1)
    parser.add_argument('--seed', type=int, default=20280101)
    parser.add_argument('--entropy', type=float, default=0.02)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--keep-episodes', action='store_true')
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if args.games < 1 or args.timeout < 30:
        parser.error('--games must be >=1 and --timeout >=30')
    if not Path(args.godot).is_file() and shutil.which(args.godot) is None:
        parser.error('Godot executable missing: ' + args.godot)
    if V5_LOCK.exists():
        raise RuntimeError('V5_TRAIN_LOCKED. Check for active processes before removing lock.')
    V5_LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(V5_LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise RuntimeError('V5_TRAIN_LOCKED. Check running processes and stale lock.')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write('pid=%d\n' % os.getpid())
        v4_sha = native_v4.sha256(V4_CHECKPOINT)
        state, model, optimizer, done = load_or_create_v5()
        validate_history(done)
        if not args.prepare_only:
            backup = V5_CHECKPOINT.parent / 'backups'
            backup.mkdir(parents=True, exist_ok=True)
            dest = backup / ('brwr_policy_v5_before_training_games%d_%s.pt' %
                             (done, datetime.now().strftime('%Y%m%d_%H%M%S')))
            shutil.copy2(V5_CHECKPOINT, dest)
            print('V5_CHECKPOINT_BACKUP_OK ' + str(dest), flush=True)
        preflight(args.godot, model, done)
        if args.prepare_only:
            print('V5_PREPARE_COMPLETE v5_games=%d v4_unchanged=1' % done, flush=True)
            return
        for offset, (bots, avatar, difficulty) in enumerate(
                native_v4.advance_scenario(args.seed, done, args.games, False)):
            game_no = done + offset + 1
            match_seed = args.seed + game_no
            export_v5(model, game_no - 1)
            print('V5_GAME_START %d seed=%d bots=%d avatar=%s/%s' %
                  (game_no, match_seed, bots, avatar, difficulty), flush=True)
            end, exp, episode, log, elapsed = run_episode(args.godot, match_seed, bots, avatar, difficulty, args.timeout)
            rewards = v4.rewards_from_result(end, bots)
            loss = v4.update_from_episode(model, optimizer, exp, rewards, args.entropy)
            save_checkpoint(state, model, optimizer, game_no)
            export_v5(model, game_no)
            append_history([game_no, match_seed, bots, avatar, difficulty, end.get('round', ''),
                            len(exp), end.get('winner', ''),
                            json.dumps([round(x, 4) for x in rewards]), round(loss, 6),
                            state.get('initialized_from_v4_games', 500)])
            print('V5_GAME_SAVED %d decisions=%d godot_seconds=%.2f winner=%s loss=%.5f checkpoint_v5_games=%d log=%s' %
                  (game_no, len(exp), elapsed, end.get('winner'), loss, game_no, log), flush=True)
            if not args.keep_episodes:
                # Delete only after successful persistent checkpoint. Preserve tracked files.
                rel = episode.relative_to(ROOT).as_posix()
                tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', '--', rel],
                                         cwd=ROOT, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL) if shutil.which('git') else None
                if tracked is not None and tracked.returncode != 0:
                    episode.unlink(missing_ok=True)
                    print('  V5_EPISODE_JSONL_CLEANED after_checkpoint=1', flush=True)
                else:
                    print('  V5_EPISODE_JSONL_RETAINED git_tracked_or_missing=1', flush=True)
        if native_v4.sha256(V4_CHECKPOINT) != v4_sha:
            raise RuntimeError('Original v4 checkpoint changed while training v5')
        print('V5_TRAIN_COMPLETE from=%d to=%d v4_checkpoint_untouched=1' %
              (done, done + args.games), flush=True)
    finally:
        V5_LOCK.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        train()
    except (Exception, KeyboardInterrupt) as exc:
        print('V5_TRAIN_STOP %s: %s' % (type(exc).__name__, exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
