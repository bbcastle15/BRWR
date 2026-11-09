"""Audit v4 episodes from Godot for choice coverage and private-state leakage."""
import argparse
import collections
import json
from pathlib import Path


def audit(path: Path) -> None:
    phases = collections.Counter()
    candidates = []
    prep_sides = collections.Counter()
    prep_selections = collections.Counter()
    transitions = 0
    end = None
    leak = 0
    wrong_choice = 0
    with path.open(encoding="utf-8") as inp:
        for line in inp:
            if not line.strip():
                continue
            entry = json.loads(line)
            if entry.get("record_type") == "episode_end":
                end = entry
                continue
            if entry.get("record_type") != "transition":
                continue
            transitions += 1
            owner = int(entry.get("player_index", -1))
            players = entry.get("observation", {}).get("players", [])
            for i, data in enumerate(players):
                if i != owner and ("hand" in data or "quick_spell" in data or "ready_spells" in data):
                    leak += 1
            options = entry.get("legal_candidates", [])
            choice = int(entry.get("selected_candidate_id", -1))
            if not (0 <= choice < len(options)):
                wrong_choice += 1
            candidates.append(len(options))
            stage = entry.get("substep", "")
            phases[(entry.get("request_type", ""), stage)] += 1
            if entry.get("request_type") == "preparation" and stage in ("ready_side", "quick_side"):
                present = {c.get("detail", {}).get("side", "") for c in options}
                if "Light" in present:
                    prep_sides["light_available"] += 1
                if "Dark" in present:
                    prep_sides["dark_available"] += 1
                if 0 <= choice < len(options):
                    prep_selections[options[choice].get("detail", {}).get("side", "")] += 1
    print(f"File: {path}")
    print(f"Transitions: {transitions}, candidates per decision max: {max(candidates, default=0)}")
    print(f"Side options: {dict(prep_sides)}, selected: {dict(prep_selections)}")
    print(f"Invalid candidate indices: {wrong_choice}, observations with opponent private hand fields: {leak}")
    print(f"Stages: {dict(phases)}")
    print(f"Episode end: {bool(end)}, winner: {end.get('winner') if end else 'not recorded'}")
    if leak or wrong_choice or end is None:
        raise SystemExit("AUDIT_FAIL")
    print("AUDIT_PASS")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("episode", type=Path)
    args = parser.parse_args()
    audit(args.episode)
