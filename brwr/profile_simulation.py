"""BRWR profiling replay. Loads a checkpoint, never trains or saves it.

Usage from brwr:
  python profile_simulation.py --godot "C:\\path\\to\\Godot_console.exe" --games 3
Requires profile_worker_patch.py to have generated ai/ai_policy_match_profile.gd.
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "ai" / "python"))
import torch
import train

# Fixed, varied scenarios; no scheduler shuffle and no optimizer updates.
SCENARIOS: tuple[tuple[int, str, str], ...] = (
    (4, "none", "apprentice"),
    (3, "possessed", "apprentice"),
    (6, "none", "apprentice"),
    (2, "none", "apprentice"),
    (5, "possessed", "apprentice"),
)


def read_profile_end(dataset_file: Path) -> dict[str, Any]:
    if not dataset_file.is_file():
        raise RuntimeError(f"Dataset di profiling assente: {dataset_file}")
    end: dict[str, Any] | None = None
    with dataset_file.open(encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            if row.get("record_type") == "episode_end":
                end = row
    if end is None:
        raise RuntimeError(f"episode_end assente: {dataset_file}")
    return end


def read_godot_profile(log_file: Path) -> dict[str, Any]:
    marker = "AI_PROFILE_JSON "
    last: dict[str, Any] | None = None
    with log_file.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if line.startswith(marker):
                last = json.loads(line[len(marker):])
    if last is None:
        tail = "".join(log_file.read_text(encoding="utf-8", errors="replace").splitlines(True)[-25:])
        raise RuntimeError("Profiling Godot assente. Ultime righe:\n" + tail)
    return last


def one_game(godot: str, seed: int, bots: int, avatar: str, difficulty: str,
             model: train.ActionPolicy, log_dir: Path) -> dict[str, Any]:
    runtime = ROOT / "ai" / "runtime"
    dataset = ROOT / "ai" / "datasets"
    runtime.mkdir(parents=True, exist_ok=True)
    dataset.mkdir(parents=True, exist_ok=True)
    # Same single-session IPC convention used by train.py. Never run concurrently.
    for pattern in ("request_*.json", "response_*.json"):
        for file in runtime.glob(pattern):
            file.unlink()

    scenario = f"h{bots}_av{avatar}_{difficulty if avatar != 'none' else 'na'}_normal"
    episode_path = dataset / f"profile_episode_{seed}_{scenario}.jsonl"
    godot_log = log_dir / f"godot_{seed}_{scenario}.log"
    command = [godot, "--headless", "--path", str(ROOT), "--script",
               "res://ai/ai_policy_match_profile.gd", "--", str(seed), str(bots),
               avatar, difficulty, "normal"]
    metrics: dict[str, float] = defaultdict(float)
    count = 0
    step_number = 1
    step_last_sent = time.perf_counter()
    total_begin = time.perf_counter()
    with godot_log.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        step_last_sent = time.perf_counter()
        try:
            while process.poll() is None:
                path = runtime / f"request_{step_number:06}.json"
                ts = time.perf_counter()
                available = path.is_file()
                metrics["request_file_check_ms"] += 1000.0 * (time.perf_counter() - ts)
                metrics["request_poll_count"] += 1
                if not available:
                    if time.perf_counter() - step_last_sent > 130:
                        raise RuntimeError("Nessuna nuova decisione da Godot per 130 s")
                    sleep_start = time.perf_counter()
                    time.sleep(0.001)  # mirrors the optimized training polling
                    metrics["request_poll_sleep_ms"] += 1000.0 * (time.perf_counter() - sleep_start)
                    continue

                ts = time.perf_counter()
                try:
                    request = json.loads(path.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    metrics["incomplete_request_reads"] += 1
                    sleep_start = time.perf_counter()
                    time.sleep(0.001)
                    metrics["request_poll_sleep_ms"] += 1000.0 * (time.perf_counter() - sleep_start)
                    continue
                metrics["request_read_parse_ms"] += 1000.0 * (time.perf_counter() - ts)
                metrics["wait_for_godot_request_ms"] += 1000.0 * (ts - step_last_sent)
                if int(request.get("step", -1)) != step_number:
                    raise RuntimeError("IPC sequence mismatch")
                options = request["decision"].get("candidates", [])
                if not options:
                    raise RuntimeError("Godot non ha proposto azioni legali")

                ts = time.perf_counter()
                features = torch.tensor([
                    train.encode_action(request["observation"], request["decision"], option, idx, len(options))
                    for idx, option in enumerate(options)
                ], dtype=torch.float32)
                metrics["feature_encoding_ms"] += 1000.0 * (time.perf_counter() - ts)

                ts = time.perf_counter()
                with torch.no_grad():
                    logits = model(features)
                    probs = torch.softmax(logits, dim=0)
                    choice = int(torch.multinomial(probs, 1).item())
                metrics["pytorch_inference_sampling_ms"] += 1000.0 * (time.perf_counter() - ts)

                ts = time.perf_counter()
                response = runtime / f"response_{step_number:06}.json"
                temp = response.with_suffix(".tmp")
                temp.write_text(json.dumps({"step": step_number, "choice_id": choice}), encoding="utf-8")
                temp.replace(response)
                metrics["response_write_ms"] += 1000.0 * (time.perf_counter() - ts)

                step_last_sent = time.perf_counter()
                step_number += 1
                count += 1
            exit_code = process.wait()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

    total_ms = (time.perf_counter() - total_begin) * 1000.0
    metrics["wait_after_last_response_ms"] = 1000.0 * (time.perf_counter() - step_last_sent)
    if exit_code != 0:
        tail = "\n".join(godot_log.read_text(encoding="utf-8", errors="replace").splitlines()[-35:])
        raise RuntimeError(f"Godot exit={exit_code}. Ultimo log:\n{tail}")
    godot_metrics = read_godot_profile(godot_log)
    end = read_profile_end(episode_path)
    if int(end.get("decisions", -1)) != count:
        raise RuntimeError(f"Decision count differente: Python={count}, Godot={end.get('decisions')}")

    return {
        "seed": seed, "scenario": scenario, "bots": bots, "avatar": avatar,
        "decisions": count, "winner": end.get("winner"), "round": end.get("round"),
        "wall_ms": round(total_ms, 3),
        "python": {k: round(v, 3) for k, v in metrics.items()},
        "godot": godot_metrics,
        "log": str(godot_log.relative_to(ROOT)),
    }


def aggregated(games: list[dict[str, Any]]) -> dict[str, Any]:
    wall = sum(g["wall_ms"] for g in games)
    decisions = sum(g["decisions"] for g in games)
    python: dict[str, float] = defaultdict(float)
    godot: dict[str, float] = defaultdict(float)
    for game in games:
        for k, v in game["python"].items():
            python[k] += float(v)
        for k, v in game["godot"].items():
            godot[k] += float(v)
    return {
        "games": len(games), "decisions": decisions, "wall_ms": round(wall, 3),
        "ms_per_game": round(wall / len(games), 3),
        "ms_per_decision": round(wall / max(1, decisions), 3),
        "python": {k: round(v, 3) for k, v in sorted(python.items())},
        "godot": {k: round(v, 3) for k, v in sorted(godot.items())},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="BRWR profiler: no training, no checkpoint writes")
    parser.add_argument("--godot", required=True)
    parser.add_argument("--games", type=int, default=3)
    parser.add_argument("--seed", type=int, default=20280101)
    args = parser.parse_args()
    if not 1 <= args.games <= 20:
        parser.error("--games deve essere fra 1 e 20")
    if not (ROOT / "project.godot").is_file():
        parser.error("Lo script deve trovarsi nella cartella brwr, insieme a project.godot")
    if not (ROOT / "ai" / "ai_policy_match_profile.gd").is_file():
        parser.error("Genera prima la copia con profile_worker_patch.py")
    if not Path(args.godot).is_file() and not shutil.which(args.godot):
        parser.error("Eseguibile Godot non trovato")
    checkpoint_path = ROOT / "ai" / "model" / "brwr_policy_v4.pt"
    if not checkpoint_path.is_file():
        parser.error(f"Checkpoint assente: {checkpoint_path}")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = ROOT / "ai" / "profile_logs" / timestamp
    log_dir.mkdir(parents=True, exist_ok=False)

    torch.manual_seed(args.seed)
    model = train.ActionPolicy()
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    model.load_state_dict(checkpoint["model"])
    model.eval()
    print(f"Checkpoint letto: {checkpoint.get('games_completed', 'n/d')} partite. Nessun aggiornamento o salvataggio.", flush=True)
    print(f"Log: {log_dir}", flush=True)
    results: list[dict[str, Any]] = []
    for k in range(args.games):
        bots, avatar, diff = SCENARIOS[k % len(SCENARIOS)]
        seed = args.seed + k
        print(f"PROFILING {k+1}/{args.games} seed={seed} bots={bots} avatar={avatar}", flush=True)
        try:
            result = one_game(args.godot, seed, bots, avatar, diff, model, log_dir)
        except Exception as exc:
            (log_dir / "ERROR.txt").write_text(str(exc), encoding="utf-8")
            print("ERRORE:", exc, file=sys.stderr, flush=True)
            raise
        results.append(result)
        print(f"  COMPLETATA: {result['wall_ms']/1000:.2f} s, decisions={result['decisions']}, "
              f"{result['wall_ms']/max(1,result['decisions']):.1f} ms/decisione", flush=True)
        (log_dir / "details.json").write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")

    report = aggregated(results)
    (log_dir / "summary.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    with (log_dir / "games.csv").open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(["seed", "scenario", "decisions", "wall_s", "ms_per_decision", "winner"])
        for game in results:
            writer.writerow([game["seed"], game["scenario"], game["decisions"],
                             round(game["wall_ms"]/1000.0, 3),
                             round(game["wall_ms"]/max(1,game["decisions"]), 3), game["winner"]])

    p, g = report["python"], report["godot"]
    print("\n============== BRWR PROFILE ==============", flush=True)
    print(f"Partite: {report['games']}; decisioni: {report['decisions']}; "
          f"tempo totale: {report['wall_ms']/1000:.2f} s; "
          f"media: {report['ms_per_game']/1000:.2f} s/partita; "
          f"{report['ms_per_decision']:.2f} ms/decisione", flush=True)
    print("--- Python (tempi cumulativi) ---", flush=True)
    for key in ("wait_for_godot_request_ms", "request_poll_sleep_ms", "request_read_parse_ms",
                "feature_encoding_ms", "pytorch_inference_sampling_ms", "response_write_ms",
                "wait_after_last_response_ms"):
        print(f"  {key:34s} {p.get(key, 0)/1000:9.3f} s", flush=True)
    print("--- Godot (tempi cumulativi) ---", flush=True)
    for key in ("bridge_decision_ms", "bridge_observation_ms", "bridge_step_ms", "dataset_store_ms",
                "request_write_ms", "response_wait_ms", "response_read_ms", "response_poll_file_check_ms",
                "frame_and_engine_ms"):
        print(f"  {key:34s} {g.get(key, 0)/1000:9.3f} s", flush=True)
    print(f"Controlli Python: {int(p.get('request_poll_count', 0))} | "
          f"Godot: {int(g.get('response_poll_count', 0))}", flush=True)
    print("NOTA: i tempi di attesa Python e Godot si sovrappongono; non sommarli.", flush=True)
    print("'frame_and_engine' comprende anche il passaggio dei frame, non solo CPU di gioco.", flush=True)
    print(f"Report: {log_dir / 'summary.json'}", flush=True)
    print("PROFILE_COMPLETE. Checkpoint invariato.", flush=True)
    print("==========================================", flush=True)


if __name__ == "__main__":
    main()
