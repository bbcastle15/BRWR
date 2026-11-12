#!/usr/bin/env python3
"""BRWR v4: safe on-policy training using the validated native Godot runner.

One FRESH Godot process per episode (NOT the unvalidated persistent batch).
The GDScript policy samples actions from the exported current PyTorch weights;
Python replays exactly those selected actions to compute on-policy REINFORCE.

Does not modify game.gd, game.tscn, or ai/python/train.py.
Usage from BRWR/brwr:
  python ai/python/train_optimized_native.py --godot PATH --games 1
  python ai/python/train_optimized_native.py --godot PATH --games 100
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ai" / "python"))
import train as training  # Existing canonical encoding/model/rewards/REINFORCE.
import torch

CHECKPOINT = ROOT / "ai" / "model" / "brwr_policy_v4.pt"
NATIVE_JSON = ROOT / "ai" / "model" / "native_policy_v4.json"
HISTORY = ROOT / "ai" / "model" / "training_history.csv"
LOCK = ROOT / "ai" / "model" / "optimized_training.lock"
SCRIPT = "res://ai/ai_policy_school_prefix_match.gd"
HISTORY_HEADER = ["game", "seed", "bots", "avatar", "difficulty", "round", "decisions", "winner", "rewards", "loss"]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args: list[str], *, label: str, timeout: int = 300) -> str:
    print(f"[setup] {label}", flush=True)
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, encoding="utf-8", errors="replace", timeout=timeout)
    output = result.stdout or ""
    if result.returncode != 0:
        raise RuntimeError(f"{label}: exit={result.returncode}\n" + "\n".join(output.splitlines()[-50:]))
    for line in output.splitlines():
        if any(tag in line for tag in ("_OK", "_VERIFIED", "SCHOOL_CACHE_", "mismatches=")):
            print("  " + line.strip(), flush=True)
    return output


def preflight(godot: str, python: str) -> None:
    required = [
        ROOT / "project.godot", ROOT / "game.gd", ROOT / "game.tscn", CHECKPOINT,
        ROOT / "ai/python/train.py", ROOT / "ai/python/export_native_policy_v4.py",
        ROOT / "make_native_worker.py", ROOT / "build_school_cache_variant.py",
        ROOT / "prepare_school_cache.py", ROOT / "build_policy_prefix_variant.py",
        ROOT / "ai/ai_native_policy_validation.gd",
        ROOT / "ai/ai_native_policy_prefix_validation.gd",
    ]
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file()]
    if missing:
        raise RuntimeError("Missing required Git-synced files:\n  " + "\n  ".join(missing))
    if not Path(godot).is_file() and shutil.which(godot) is None:
        raise RuntimeError(f"Godot executable not found: {godot}")
    protected = [ROOT / "game.gd", ROOT / "game.tscn", ROOT / "ai/python/train.py"]
    before = {str(p): sha256(p) for p in protected}
    command([python, str(ROOT / "ai/python/export_native_policy_v4.py")], label="Export checkpoint to native weights")
    command([python, str(ROOT / "make_native_worker.py")], label="Generate original native worker")
    command([python, str(ROOT / "build_school_cache_variant.py")], label="Build cached Game with UI guards")
    command([python, str(ROOT / "prepare_school_cache.py")], label="Validate school cache manifest")
    command([python, str(ROOT / "build_policy_prefix_variant.py")], label="Build shared-prefix policy")
    cached = (ROOT / "ai/game_school_cached.gd").read_text(encoding="utf-8-sig")
    for name in ("refresh_all_player_boards", "refresh_player_board", "_refresh_damage_boards"):
        anchor = "func " + name + "("
        at = cached.find(anchor)
        if at < 0 or "if not enable_beta_hud:\n\t\treturn" not in cached[at:at+350]:
            raise RuntimeError("Missing verified UI guard: " + name)
    generated = ROOT / "ai/ai_policy_school_prefix_match.gd"
    if not generated.is_file() or 'load("res://ai/game_school_cached.tscn")' not in generated.read_text(encoding="utf-8-sig"):
        raise RuntimeError("Prefix worker does not reference isolated cached game")
    command([godot, "--headless", "--path", str(ROOT), "--script", "res://ai/ai_native_policy_validation.gd"], label="Original policy parity", timeout=180)
    prefix_out = command([godot, "--headless", "--path", str(ROOT), "--script", "res://ai/ai_native_policy_prefix_validation.gd"], label="Prefix policy parity", timeout=180)
    if "POLICY_PREFIX_PARITY" not in prefix_out or "mismatches=0" not in prefix_out:
        raise RuntimeError("Prefix policy parity did not explicitly pass")
    for p in protected:
        if sha256(p) != before[str(p)]:
            raise RuntimeError("Protected original code changed during setup: " + str(p))
    print("[setup] FAST_TRAIN_SETUP_OK | original game/train unchanged", flush=True)


def native_weights(document: dict[str, Any], model: training.ActionPolicy, games: int) -> None:
    """Write current PyTorch weights in the existing native V4 JSON schema.

    Keep original token-bucket cache; uncached strings still get exact BLAKE2b
    in GDScript. This does not modify the policy's feature mapping.
    """
    if document.get("format") != "BRWR_NATIVE_V4_1":
        raise RuntimeError("Unexpected native JSON format")
    if int(document.get("feature_dim", -1)) != training.FEATURE_DIM:
        raise RuntimeError("Native/PyTorch feature dimension mismatch")
    for layer, position in enumerate((0, 2, 4)):
        linear = model.net[position]
        document[f"w{layer}"] = linear.weight.detach().cpu().reshape(-1).tolist()
        document[f"b{layer}"] = linear.bias.detach().cpu().tolist()
    document["checkpoint_games"] = games
    NATIVE_JSON.parent.mkdir(parents=True, exist_ok=True)
    tmp = NATIVE_JSON.with_name(NATIVE_JSON.name + ".tmp")
    tmp.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    os.replace(tmp, NATIVE_JSON)


def parse_episode(path: Path, expected_seed: int, bots: int) -> tuple[dict, list[training.Experience]]:
    if not path.is_file() or path.stat().st_size < 50:
        raise RuntimeError(f"Missing/empty episode: {path}")
    experiences = []
    header = None
    end = None
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Broken episode JSONL at line {line_number}: {exc}") from exc
            kind = record.get("record_type")
            if kind == "episode_start":
                if header is not None or count:
                    raise RuntimeError("Duplicated/unexpected episode_start")
                header = record
            elif kind == "transition":
                if header is None or end is not None:
                    raise RuntimeError("Transition outside episode")
                count += 1
                if int(record.get("step", -1)) != count or int(record.get("seed", -1)) != expected_seed:
                    raise RuntimeError(f"Transition step/seed mismatch at line {line_number}")
                player = int(record["player_index"])
                if not 0 <= player < bots:
                    raise RuntimeError(f"Invalid player {player} at transition {count}")
                candidates = record["legal_candidates"]
                chosen = int(record["selected_candidate_id"])
                if not isinstance(candidates, list) or not (0 <= chosen < len(candidates)):
                    raise RuntimeError(f"Invalid native chosen action at transition {count}")
                observation = record["observation"]
                decision = {"player_index": player, "type": record.get("request_type", ""),
                            "substep": record.get("substep", ""), "candidates": candidates}
                features = torch.tensor([training.encode_action(observation, decision, c, i, len(candidates))
                                         for i, c in enumerate(candidates)], dtype=torch.float32)
                experiences.append(training.Experience(player, features, chosen))
            elif kind == "episode_end":
                if header is None or end is not None:
                    raise RuntimeError("Missing start or duplicated episode_end")
                end = record
            else:
                raise RuntimeError(f"Unknown JSONL record type {kind!r} at line {line_number}")
    if header is None or end is None:
        raise RuntimeError("Incomplete episode (start/end missing)")
    if int(header.get("seed", -1)) != expected_seed or int(end.get("seed", -1)) != expected_seed:
        raise RuntimeError("Episode seed mismatch")
    if int(header.get("human_player_count", -1)) != bots or int(end.get("human_player_count", -1)) != bots:
        raise RuntimeError("Episode bot count mismatch")
    if count <= 0 or int(end.get("decisions", -1)) != count:
        raise RuntimeError(f"Episode decisions mismatch: lines={count}, declared={end.get('decisions')}")
    return end, experiences


def run_episode(godot: str, seed: int, bots: int, avatar: str, difficulty: str,
                timeout: int) -> tuple[dict, list[training.Experience], Path, Path, float]:
    log_dir = ROOT / "ai" / "runtime"
    log_dir.mkdir(parents=True, exist_ok=True)
    scenario = f"h{bots}_av{avatar}_{difficulty if avatar != 'none' else 'na'}_normal"
    destination = ROOT / "ai" / "datasets" / f"school_prefix_episode_{seed}_{scenario}.jsonl"
    if destination.exists():
        archive_dir = ROOT / "ai" / "datasets" / "replaced_before_native_training"
        archive_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        archive = archive_dir / (destination.name + "." + stamp + ".previous")
        destination.replace(archive)
        print(f"  [safety] Existing episode archived: {archive}", flush=True)
    log = log_dir / f"optimized_training_seed_{seed}.log"
    cmd = [godot, "--headless", "--path", str(ROOT), "--script", SCRIPT, "--",
           str(seed), str(bots), avatar, difficulty, "normal"]
    start = time.perf_counter()
    with log.open("w", encoding="utf-8", errors="replace") as file:
        try:
            run = subprocess.run(cmd, cwd=ROOT, stdout=file, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"Godot episode exceeded {timeout}s. Inspect {log}") from exc
    elapsed = time.perf_counter() - start
    output = log.read_text(encoding="utf-8", errors="replace")
    if run.returncode != 0 or "AI_EPISODE_COMPLETE seed=" not in output:
        tail = "\n".join(output.splitlines()[-50:])
        raise RuntimeError(f"Godot episode failed (exit={run.returncode}). Log: {log}\n{tail}")
    match = re.search(r"(?m)^AI_EPISODE_FILE\s+(.+?)\s*$", output)
    if match is None:
        raise RuntimeError(f"Missing AI_EPISODE_FILE marker. Log: {log}")
    reported = Path(match.group(1).strip())
    if reported.resolve() != destination.resolve():
        raise RuntimeError(f"Output path mismatch: expected {destination}, Godot reported {reported}")
    end, experiences = parse_episode(destination, seed, bots)
    return end, experiences, destination, log, elapsed


def advance_scenario(seed: int, start_game: int, count: int, apprentice_only: bool):
    """Stable absolute-game schedule, avoiding a shuffle reset on --resume."""
    choices = training.scenarios(apprentice_only)
    rng = random.Random(seed)
    for offset in range(start_game + count):
        if offset % len(choices) == 0:
            rng.shuffle(choices)
        if offset >= start_game:
            yield choices[offset % len(choices)]


def atomic_checkpoint(original: dict, model: training.ActionPolicy,
                      opt: torch.optim.Optimizer, game_no: int) -> None:
    payload = dict(original)
    payload.update({"model": model.state_dict(), "optimizer": opt.state_dict(),
                    "games_completed": game_no, "feature_dim": training.FEATURE_DIM})
    temporary = CHECKPOINT.with_name(CHECKPOINT.name + ".optimized-tmp")
    torch.save(payload, temporary)
    os.replace(temporary, CHECKPOINT)


def append_history(row: list) -> None:
    if HISTORY.exists() and HISTORY.stat().st_size:
        with HISTORY.open("r", encoding="utf-8", newline="") as file:
            header = next(csv.reader(file), [])
        if header != HISTORY_HEADER:
            raise RuntimeError(f"Unexpected training_history.csv columns: {header}")
    else:
        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        with HISTORY.open("w", newline="", encoding="utf-8") as file:
            csv.writer(file).writerow(HISTORY_HEADER)
    with HISTORY.open("a", newline="", encoding="utf-8") as file:
        csv.writer(file).writerow(row)


def main() -> None:
    ap = argparse.ArgumentParser(description="BRWR optimized native on-policy REINFORCE trainer")
    ap.add_argument("--godot", required=True, help="Path to Godot console executable")
    ap.add_argument("--games", type=int, default=1, help="Additional games, default 1 for smoke test")
    ap.add_argument("--seed", type=int, default=20270101, help="Base seed used by the original trainer")
    ap.add_argument("--lr", type=float, default=0.0005)
    ap.add_argument("--entropy", type=float, default=0.02)
    ap.add_argument("--apprentice-only", action="store_true")
    ap.add_argument("--keep-episodes", action="store_true", help="Keep large native JSONL after checkpoint is saved")
    ap.add_argument("--timeout", type=int, default=240, help="Timeout for each Godot episode in seconds")
    ap.add_argument("--prepare-only", action="store_true", help="Check environment without training")
    args = ap.parse_args()
    if args.games < 1 or args.timeout < 30 or args.lr <= 0:
        ap.error("Require games >= 1, timeout >= 30 and lr > 0")
    if not CHECKPOINT.is_file():
        ap.error("Missing ai/model/brwr_policy_v4.pt. Restore the real checkpoint from GitHub before proceeding.")
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        raise SystemExit("TRAIN_LOCKED: another run may be active. Check processes; remove ai/model/optimized_training.lock only if stale.")
    try:
        os.write(fd, f"pid={os.getpid()} at={datetime.now().isoformat()}\n".encode())
        os.close(fd)
        original_hash = sha256(CHECKPOINT)
        state = torch.load(CHECKPOINT, map_location="cpu", weights_only=False)
        games_done = int(state.get("games_completed", -1))
        if games_done < 399:
            raise RuntimeError(f"Checkpoint is too old (games_completed={games_done}); expected at least 399 after Git sync")
        if int(state.get("feature_dim", training.FEATURE_DIM)) != training.FEATURE_DIM:
            raise RuntimeError("Checkpoint feature dimension does not match train.py")
        model = training.ActionPolicy()
        model.load_state_dict(state["model"])
        optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
        if "optimizer" not in state:
            raise RuntimeError("Checkpoint missing optimizer state; cannot resume the same training")
        optimizer.load_state_dict(state["optimizer"])
        print(f"RESUME_CHECKPOINT_OK completed={games_done} sha256={original_hash[:16]} feature_dim={training.FEATURE_DIM}", flush=True)
        # Preserve optimizer's existing learning rate when resuming, as in train.py.
        print(f"OPTIMIZER_RESUMED lr={[g['lr'] for g in optimizer.param_groups]} entropy={args.entropy}", flush=True)
        if not args.prepare_only:
            backup_folder = CHECKPOINT.parent / "backups"
            backup_folder.mkdir(parents=True, exist_ok=True)
            dest = backup_folder / f"brwr_policy_v4_before_fast_train_games{games_done}_{datetime.now():%Y%m%d_%H%M%S}.pt"
            shutil.copy2(CHECKPOINT, dest)
            print(f"CHECKPOINT_BACKUP_OK {dest}", flush=True)
        preflight(args.godot, sys.executable)
        doc = json.loads(NATIVE_JSON.read_text(encoding="utf-8"))
        if args.prepare_only:
            if sha256(CHECKPOINT) != original_hash:
                raise RuntimeError("Checkpoint changed during prepare-only")
            print("FAST_TRAIN_PREPARE_ONLY_OK checkpoint_unchanged=1", flush=True)
            return
        for k, (bots, avatar, difficulty) in enumerate(advance_scenario(args.seed, games_done, args.games, args.apprentice_only)):
            game_no = games_done + k + 1
            seed = args.seed + game_no
            native_weights(doc, model, game_no - 1)
            print(f"GAME_START {game_no} seed={seed} bots={bots} avatar={avatar}/{difficulty}", flush=True)
            end, experiences, episode_path, log_path, elapsed = run_episode(
                args.godot, seed, bots, avatar, difficulty, args.timeout)
            rewards = training.rewards_from_result(end, bots)
            loss = training.update_from_episode(model, optimizer, experiences, rewards, args.entropy)
            # Only now that the entire episode and its update succeeded do we commit.
            atomic_checkpoint(state, model, optimizer, game_no)
            native_weights(doc, model, game_no)
            append_history([game_no, seed, bots, avatar, difficulty, end.get("round", ""),
                            len(experiences), end.get("winner", ""),
                            json.dumps([round(x, 4) for x in rewards]), round(loss, 6)])
            print(f"GAME_SAVED {game_no} decisions={len(experiences)} godot_seconds={elapsed:.2f} "
                  f"winner={end['winner']} loss={loss:.5f} checkpoint_games={game_no} "
                  f"log={log_path}", flush=True)
            if not args.keep_episodes:
                # The full experience is already consumed by the on-policy update.
                # Keep the checkpoint, optimizer and CSV; remove only this new JSONL.
                # Avoid deleting anything already tracked by Git.
                rel = episode_path.relative_to(ROOT).as_posix()
                tracked = subprocess.run(["git", "ls-files", "--error-unmatch", "--", rel],
                                         cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if shutil.which("git") else None
                if tracked is not None and tracked.returncode != 0:
                    episode_path.unlink(missing_ok=True)
                    print("  EPISODE_JSONL_CLEANED post_checkpoint=1", flush=True)
                else:
                    print("  EPISODE_JSONL_RETAINED tracked_or_git_missing=1", flush=True)
        print(f"OPTIMIZED_TRAIN_COMPLETE from={games_done} to={games_done+args.games} "
              f"checkpoint={CHECKPOINT}", flush=True)
    finally:
        LOCK.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as err:
        print(f"OPTIMIZED_TRAIN_STOP: {type(err).__name__}: {err}", file=sys.stderr, flush=True)
        sys.exit(1)
