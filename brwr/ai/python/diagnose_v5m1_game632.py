#!/usr/bin/env python3
"""Read-only BRWR V5M1 event-draw failure diagnostic for game 632.

Reads source, event definitions, and existing logs only; creates one report and
one ZIP evidence bundle. Does not launch Godot, load a model, or change training.
"""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
from zipfile import ZipFile, ZIP_DEFLATED

DEFAULT_SEED = 20350101 + 632
REPORT_NAME = 'v5m1_game632_event_draw_diagnostic.txt'
BUNDLE_NAME = 'v5m1_game632_event_draw_evidence.zip'
PATTERNS = [
    re.compile(x, re.I) for x in [
        r'V5M1_GAME_START\s+632', r'Event Deck Moon\s+\d+\s+is empty',
        r'Black Rose Phase:\s*Event draw failed', r'AI_EPISODE_STOP',
        r'Game idle for too many frames', r'V5M1_CHECKPOINT',
        r'Event Deck Moon\s+\d+:', r'GAME: Moon changed',
        r'place_event_on_board:\s*invalid slot',
        r'V5M1_TRAIN_STOP', r'ROUND\s+\d+\s+COMPLETE',
    ]
]


def read_limited(path: Path, max_bytes: int = 8_000_000) -> str:
    try:
        if path.stat().st_size <= max_bytes:
            return path.read_text(encoding='utf-8-sig', errors='replace')
        with path.open('rb') as fh:
            fh.seek(max(0, path.stat().st_size - max_bytes))
            return '[TRUNCATED TO TAIL]\n' + fh.read().decode('utf-8', errors='replace')
    except (OSError, UnicodeError) as exc:
        return '[READ_FAILED %s]' % exc


def interesting_lines(value: str, before: int = 8, after: int = 14, cap: int = 150) -> str:
    lines = value.splitlines()
    idx = [n for n, line in enumerate(lines) if any(p.search(line) for p in PATTERNS)]
    if not idx:
        return '[NO MATCHING RUNTIME LINES IN THIS LOG]'
    keep = set()
    for n in idx[-cap:]:
        keep.update(range(max(0, n - before), min(len(lines), n + after + 1)))
    return '\n'.join('%6d | %s' % (n + 1, lines[n][:550]) for n in sorted(keep))


def event_counts(path: Path) -> str:
    if not path.is_file():
        return 'EVENT_DEFINITIONS_NOT_FOUND: %s' % path
    try:
        data = json.loads(read_limited(path, max_bytes=30_000_000))
    except (ValueError, OSError) as exc:
        return 'EVENT_DEFINITIONS_PARSE_ERROR: %s' % exc
    if isinstance(data, dict):
        data = data.get('events', data.get('cards', data))
    if not isinstance(data, list):
        return 'EVENT_DEFINITIONS_UNEXPECTED_STRUCTURE: %s' % type(data).__name__
    moon = Counter()
    slots = Counter()
    phases = Counter()
    for ev in data:
        if not isinstance(ev, dict):
            continue
        moon[str(ev.get('moon', 'MISSING'))] += 1
        slots[str(ev.get('moon', '?')) + '/' + str(ev.get('slot', '?'))] += 1
        phases[str(ev.get('moon', '?')) + '/' + str(ev.get('phase', '?'))] += 1
    return '\n'.join([
        'EVENT_DEFINITIONS_TOTAL %d' % len(data),
        'CARDS_PER_MOON ' + json.dumps(dict(sorted(moon.items())), ensure_ascii=False),
        'SLOT_COUNTS ' + json.dumps(dict(sorted(slots.items())), ensure_ascii=False),
        'PHASE_COUNTS ' + json.dumps(dict(sorted(phases.items())), ensure_ascii=False),
    ])


def method_excerpt(path: Path, method: str) -> str:
    if not path.is_file():
        return '[SOURCE MISSING] %s' % path
    text = read_limited(path, max_bytes=3_000_000)
    lines = text.splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith('func ' + method + '(')]
    if not starts:
        return '[METHOD NOT FOUND] %s in %s' % (method, path)
    start = starts[0]
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('func ')), len(lines))
    return '\n'.join('%5d %s' % (i + 1, lines[i]) for i in range(start, min(end, start + 115)))


def discover_event_db(root: Path) -> list[Path]:
    matches = []
    for directory in [root / 'scripts', root / 'ai', root]:
        if not directory.is_dir():
            continue
        for p in directory.glob('*event*database*.gd'):
            if p.is_file():
                matches.append(p)
    if matches:
        return list(dict.fromkeys(matches))[:8]
    # Targeted search through .gd files; avoid cache, addons, and giant files.
    for top in [root / 'scripts', root / 'game', root / 'src']:
        if not top.is_dir():
            continue
        for p in top.rglob('*.gd'):
            try:
                if p.stat().st_size > 1_000_000:
                    continue
                head = p.read_text(encoding='utf-8', errors='replace')
                if 'class_name EventDatabase' in head or 'func get_events_for_moon(' in head:
                    matches.append(p)
            except OSError:
                pass
    return list(dict.fromkeys(matches))[:8]


def diagnostic(root: Path) -> tuple[str, list[Path]]:
    dataset = root / 'ai' / 'datasets'
    primary_log_dir = dataset / 'v5m1_run_logs'
    logs = list(primary_log_dir.glob('v5m1_pilot_from599_*.txt')) if primary_log_dir.is_dir() else []
    logs = sorted(logs, key=lambda p: p.stat().st_mtime, reverse=True)[:3]
    for directory in [dataset, dataset / 'logs', root / 'ai']:
        if directory.is_dir():
            logs.extend(p for p in directory.glob('*20350733*') if p.is_file() and p.suffix.lower() in ('.txt', '.log', '.json'))
    logs = list(dict.fromkeys(logs))[:15]
    event_path = root / 'data' / 'events.json'
    if not event_path.is_file():
        event_path = root / 'events.json'
    game_path = root / 'ai' / 'game_school_cached.gd'
    if not game_path.is_file():
        game_path = root / 'game.gd'
    texts = [
        'BRWR V5M1 GAME 632 EVENT DRAW FAILURE — READ ONLY DIAGNOSTIC',
        'Generated: ' + datetime.now().isoformat(timespec='seconds'),
        'Project: ' + str(root),
        'Expected failed game=632 seed=%d (default seed 20350101 assumed)' % DEFAULT_SEED,
        'Original checkpoint / history / data NOT MODIFIED',
        '', 'EVENT DEFINITIONS', event_counts(event_path),
        '', 'GODOT SOURCE — draw_event()', method_excerpt(game_path, 'draw_event'),
        '', 'GODOT SOURCE — create_event_decks()', method_excerpt(game_path, 'create_event_decks'),
        '', 'GODOT SOURCE — resolve_black_rose_phase()', method_excerpt(game_path, 'resolve_black_rose_phase'),
        '', 'RUNTIME LOGS FOUND: %d' % len(logs),
    ]
    observed_empty = []
    for log in logs:
        contents = read_limited(log)
        empties = re.findall(r'Event Deck Moon\s+(\d+)\s+is empty', contents, flags=re.I)
        if empties:
            observed_empty.extend(empties)
        texts += ['', 'LOG: %s  size=%d' % (log, log.stat().st_size), interesting_lines(contents)]
    texts += [
        '', 'PRELIMINARY CLASSIFICATION',
        ('CONFIRMED_EMPTY_MOON_DECK_FROM_LOG: ' + ', '.join(observed_empty)) if observed_empty else
        'NO_EXPLICIT_EMPTY_DECK_LOG_SEEN: no conclusion about the cause; worker may not preserve Godot stdout',
        'Do not alter event rules or reset the checkpoint based only on this report.',
    ]
    db = discover_event_db(root)
    texts += ['', 'EVENT DATABASE SOURCES FOUND: ' + ', '.join(str(p) for p in db)]
    sources = [event_path, game_path, root / 'game.gd',
               root / 'ai' / 'python' / 'train_optimized_v5.py',
               root / 'ai' / 'python' / 'train_v5_momentumone_reset.py',
               root / 'ai' / 'ai_policy_school_v5_match.gd'] + db
    return '\n'.join(texts) + '\n', [p for p in dict.fromkeys(sources) if p.is_file()]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = ap.parse_args()
    root = args.root.resolve()
    report, sources = diagnostic(root)
    (root / REPORT_NAME).write_text(report, encoding='utf-8')
    with ZipFile(root / BUNDLE_NAME, 'w', compression=ZIP_DEFLATED) as z:
        z.writestr(REPORT_NAME, report)
        for src in sources:
            if src.stat().st_size <= 4_000_000:
                z.write(src, arcname='sources/' + src.relative_to(root).as_posix())
    print('V5M1_GAME632_DIAGNOSTIC_SAVED ' + str(root / REPORT_NAME))
    print('V5M1_GAME632_EVIDENCE_BUNDLE_SAVED ' + str(root / BUNDLE_NAME))
    if 'CONFIRMED_EMPTY_MOON_DECK_FROM_LOG' in report:
        print('EVENT_DRAW_CAUSE_CONFIRMED empty_moon_deck_from_log=1')
    else:
        print('EVENT_DRAW_CAUSE_NOT_YET_CONFIRMED check_existing_Godot_output=1')
    print('READ_ONLY_OK checkpoint_unchanged=1 training_not_started=1')


if __name__ == '__main__':
    main()
