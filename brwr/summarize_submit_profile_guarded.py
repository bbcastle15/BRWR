"""Aggregate BRWR submit timing from per-match sidecar JSONs.

Usage: python summarize_submit_profile_guarded.py LOG_OR_SIDECAR [...]

Understands UTF-8 and UTF-16LE PowerShell 5.1 redirection logs as well as direct
sidecar JSON files. Never needs a Godot rerun to summarize existing profiles.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path


def stop(message: str) -> None:
    raise SystemExit(f"SUBMIT_PROFILE_SUMMARY_STOP {message}")


def marker_value(text: str, marker: str) -> str | None:
    matches = [ln.split(marker, 1)[1].strip().strip('"')
               for ln in text.splitlines() if marker in ln]
    return matches[-1] if matches else None


def decode_log(log: Path) -> str:
    """PowerShell 5.1's `*> logfile` usually writes UTF-16LE with BOM."""
    raw = log.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16")
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig")
    # Support UTF-16 with no BOM (seen with some output redirection wrappers).
    if raw[:2048].count(b"\x00") > max(20, len(raw[:2048]) // 5):
        encoding = "utf-16-le" if raw[:128][1::2].count(b"\x00") >= raw[:128][0::2].count(b"\x00") else "utf-16-be"
        return raw.decode(encoding, errors="replace")
    return raw.decode("utf-8", errors="replace")


def load_profile(input_name: str) -> tuple[dict, Path, Path]:
    source = Path(input_name)
    if not source.is_file():
        stop(f"input not found: {source}")

    if source.name.endswith(".submit_profile.json"):
        # Bypass the terminal log entirely: the runner already checked this file.
        sidecar = source
    else:
        content = decode_log(source)
        if "AI_EPISODE_COMPLETE" not in content:
            stop(f"episode did not complete: {source}\n" + "\n".join(content.splitlines()[-15:]))
        path_raw = marker_value(content, "BRWR_SUBMIT_PROFILE_FILE ")
        if not path_raw:
            episode_raw = marker_value(content, "AI_EPISODE_FILE ")
            if not episode_raw:
                stop(f"neither profile marker nor episode path found in {source}")
            path_raw = episode_raw + ".submit_profile.json"
        sidecar = Path(path_raw)
        if not sidecar.is_absolute():
            sidecar = Path.cwd() / sidecar
        if not sidecar.is_file():
            stop(f"sidecar missing: {sidecar} (from log {source})")

    try:
        data = json.loads(sidecar.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        stop(f"invalid sidecar {sidecar}: {exc}")
    for key in ("seed", "decisions", "bridge_step_us", "functions"):
        if key not in data:
            stop(f"missing '{key}' in {sidecar}")
    if not isinstance(data["functions"], dict) or not data["functions"]:
        stop(f"empty or invalid function timings in {sidecar}")
    if int(data["decisions"]) <= 0:
        stop(f"zero decisions in {sidecar}")
    return data, sidecar, source


def main() -> None:
    if len(sys.argv) < 2:
        stop("Usage: python summarize_submit_profile_guarded.py LOG [LOG ...]")

    runs = [load_profile(p) for p in sys.argv[1:]]
    seed_list = [int(data["seed"]) for data, _, _ in runs]
    decision_count = sum(int(data["decisions"]) for data, _, _ in runs)
    step_us = sum(int(data["bridge_step_us"]) for data, _, _ in runs)

    stats: dict[str, dict[str, int]] = defaultdict(lambda: {
        "calls": 0, "inclusive_us": 0, "exclusive_us": 0
    })
    for data, _, _ in runs:
        for name, values in data["functions"].items():
            for field in ("calls", "inclusive_us", "exclusive_us"):
                stats[name][field] += int(values[field])

    print("========== BRWR GUARDED SUBMIT PROFILE ==========")
    print(f"Games: {len(runs)} | seeds: {seed_list} | decisions: {decision_count}")
    print(f"bridge.step: {step_us/1e6:.3f} s total | {step_us/1000/decision_count:.2f} ms/decision")
    print("INCLUSIVE timings contain child functions; do not add them together.")
    print("--- Top functions by exclusive time ---")
    print(f"{'Function':43s} {'Calls':>7s} {'Self_s':>9s} {'Incl_s':>9s} {'Self_ms/call':>13s}")
    for name, value in sorted(stats.items(), key=lambda x: x[1]["exclusive_us"], reverse=True)[:26]:
        calls = value["calls"]
        print(f"{name[:43]:43s} {calls:7d} "
              f"{value['exclusive_us']/1e6:9.3f} "
              f"{value['inclusive_us']/1e6:9.3f} "
              f"{value['exclusive_us']/1000/max(1,calls):13.3f}")
    print("--- Relevant checkpoints (inclusive and exclusive) ---")
    tracked = [
        "refresh_all_player_boards", "refresh_player_board", "_refresh_damage_boards",
        "submit_beta_input", "_submit_beta_input_authoritative",
        "_dispatch_beta_input", "process_resolution_stack", "request_player_input",
        "clear_player_input", "_handle_resolution_completion",
        "process_spell_resolution_frame", "process_effect_sequence_resolution",
        "process_explore_resolution",
    ]
    for name in tracked:
        if name in stats:
            v = stats[name]
            print(f"{name:36s} calls={v['calls']:5d} "
                  f"incl={v['inclusive_us']/1e6:8.3f}s "
                  f"excl={v['exclusive_us']/1e6:8.3f}s")

    # Keep summary alongside the invocation logs, not in shared datasets.
    output = runs[0][2].parent / "submit_profile_guarded_summary.json"
    output.write_text(json.dumps({
        "games": len(runs), "seeds": seed_list, "decisions": decision_count,
        "bridge_step_us": step_us, "stats": dict(stats),
        "sidecars": [str(sidecar) for _, sidecar, _ in runs],
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"SUBMIT_PROFILE_COMPLETE summary={output}")
    print("=================================================")


if __name__ == "__main__":
    main()
