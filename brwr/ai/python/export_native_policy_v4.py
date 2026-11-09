"""Export existing BRWR v4 checkpoint and test vectors for pure-GDScript inference.
No training, no optimizer update, no mutation of checkpoint/history.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ai" / "python"))
import train
import torch


def tokens_for_case(obs, decision, option):
    seen = []
    real = train.hashed_bucket
    def tapped(s):
        seen.append(s)
        return real(s)
    train.hashed_bucket = tapped
    try:
        train.encode_action(obs, decision, option, 0, 1)
    finally:
        train.hashed_bucket = real
    return seen


def gather_example_cases(model, limit=8):
    cases = []
    known = set()
    sources = sorted((ROOT / "ai" / "datasets").glob("policy_episode_*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    for path in sources[:6]:
        if len(cases) >= limit:
            break
        try:
            with path.open("r", encoding="utf-8") as f:
                transition_number = 0
                for line in f:
                    if '"record_type":"transition"' not in line and '"record_type": "transition"' not in line:
                        continue
                    transition_number += 1
                    if transition_number % 19 != 0 and transition_number not in (1, 2, 3):
                        continue
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    options = row.get("legal_candidates", [])
                    if not options:
                        continue
                    obs = row["observation"]
                    decision = {
                        "player_index": row.get("player_index", -1),
                        "type": row.get("request_type", ""),
                        "substep": row.get("substep", ""),
                        "candidates": options,
                    }
                    # Preserve original option-count in features; pick up to three indices.
                    indices = sorted(set([0, len(options)//2, len(options)-1]))
                    samples = []
                    for i in indices:
                        opt = options[i]
                        feat = train.encode_action(obs, decision, opt, i, len(options))
                        with torch.no_grad():
                            score = float(model(torch.tensor([feat], dtype=torch.float32))[0])
                        expected_terms = tokens_for_case(obs, decision, opt)
                        samples.append({"index": i, "option": opt, "expected_features": feat, "expected_score": score,
                                        "expected_terms": expected_terms,
                                        "expected_buckets": [train.hashed_bucket(t) for t in expected_terms],
                                        # Godot's JSON parser represents JSON numbers as floats.
                                        # Record the original Python type for this categorical token;
                                        # otherwise selection:0 is spuriously compared to selection:0.0.
                                        "ai_select_was_int": type(opt.get("payload", {}).get("ai_select")) is int})
                        known.update(expected_terms)
                    cases.append({"source": path.name, "observation": obs,
                                  "decision": {"player_index": decision["player_index"],
                                               "type": decision["type"], "substep": decision["substep"]},
                                  "total_options": len(options), "samples": samples})
                    if len(cases) >= limit:
                        break
        except (OSError, KeyError, TypeError) as exc:
            print("Skipping example file", path.name, str(exc), flush=True)
    return cases, known


def discover_token_buckets():
    # Optional acceleration only. Unknown tokens use exact BLAKE2b in GDScript.
    known = set()
    keys = ["spell_id", "school_id", "id", "side", "evocation", "ownschool", "draw_school",
            "choose_mage_id", "choose_school_id", "choose_grimoire_id", "effect", "actionkind",
            "actiontype", "side_type", "side_target", "side_range", "req", "stage", "selection"]
    scalar = set()
    for name in ("spells.json", "mages.json", "school_specializations_v19.json",
                 "evocations.json", "rooms.json", "quests.json", "events.json"):
        p = ROOT / name
        if not p.is_file():
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError):
            continue
        stack = [data]
        while stack:
            obj = stack.pop()
            if isinstance(obj, dict):
                stack.extend(obj.values())
            elif isinstance(obj, list):
                stack.extend(obj)
            elif isinstance(obj, str) and len(obj) <= 90:
                scalar.add(obj)
    # Limit to sane game identifiers; human-readable lore strings need not be cached.
    scalar = {s for s in scalar if len(s) < 60 and re.fullmatch(r"[A-Za-z0-9_./:+-]+", s)}
    for s in scalar:
        for prefix in keys:
            known.add(prefix + ":" + s)
    for text in ["", "req:action_activation_step", "stage:ready_card", "school_id:agony"]:
        known.add(text)
    return known


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default=str(ROOT / "ai/model/brwr_policy_v4.pt"))
    parser.add_argument("--output", default=str(ROOT / "ai/model/native_policy_v4.json"))
    parser.add_argument("--probe", default=str(ROOT / "ai/model/native_policy_probe_v4.json"))
    args = parser.parse_args()
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    model = train.ActionPolicy()
    model.load_state_dict(checkpoint["model"])
    model.eval()
    if int(checkpoint.get("feature_dim", train.FEATURE_DIM)) != train.FEATURE_DIM:
        raise SystemExit("Wrong feature dimension")
    cases, tokens = gather_example_cases(model)
    tokens.update(discover_token_buckets())
    model_doc = {
        "format": "BRWR_NATIVE_V4_1",
        "feature_dim": train.FEATURE_DIM,
        "checkpoint_games": int(checkpoint.get("games_completed", -1)),
        "token_buckets": {s: train.hashed_bucket(s) for s in sorted(tokens)},
    }
    for layer, idx in enumerate([0, 2, 4]):
        linear = model.net[idx]
        model_doc[f"w{layer}"] = linear.weight.detach().cpu().reshape(-1).tolist()
        model_doc[f"b{layer}"] = linear.bias.detach().cpu().tolist()
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(model_doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    vectors = ["", "hello", "req:action_activation_step", "stage:ready_card",
               "school_id:agony", "è realmente un test", "x"*128, "y"*129]
    probe = {"checkpoint_games": model_doc["checkpoint_games"],
             "hash_tests": [{"token": s, "expected_bucket": train.hashed_bucket(s)} for s in vectors],
             "cases": cases}
    probe_path = Path(args.probe)
    probe_path.parent.mkdir(parents=True, exist_ok=True)
    probe_path.write_text(json.dumps(probe, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"MODEL_EXPORT_OK games={model_doc['checkpoint_games']} cached_tokens={len(tokens)} probe_cases={len(cases)}")
    print(f"MODEL_FILE={out}")
    print(f"PROBE_FILE={probe_path}")
    if not cases:
        print("WARNING: No policy_episode_*.jsonl files. Hash-only validation available; full parity requires episode samples.")

if __name__ == "__main__":
    main()
