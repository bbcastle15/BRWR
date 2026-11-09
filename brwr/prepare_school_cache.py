"""Invalidation manifest for the AI-only cached school eligibility list.

Fingerprints BRWR rules/data and resource inventory at the start of a batch.
Sources are hashed by content; image files use size + nanosecond mtime.
This script intentionally does NOT inspect or change game state.
"""
from pathlib import Path
import hashlib
import json
import os
import sys

ROOT = Path.cwd()
if not (ROOT / 'project.godot').exists() or not (ROOT / 'game.gd').exists():
    sys.exit('SCHOOL_CACHE_PREPARE_STOP: run from BRWR/brwr')
DIR_SKIP = {'.git', '.godot', 'ai', 'docs', '__pycache__', 'node_modules', '.venv', 'venv', 'build', 'dist', 'playtest'}
TEXT_SUFFIXES = {'.gd', '.tscn', '.tres', '.json', '.cfg'}
MEDIA_SUFFIXES = {'.png', '.webp', '.jpg', '.jpeg', '.svg', '.bmp', '.gif', '.ogg'}
TRACK = TEXT_SUFFIXES | MEDIA_SUFFIXES
H = hashlib.sha256()
H.update(b'BRWR-school-eligibility-v1\0')
files = []
for directory, subdirs, filenames in os.walk(ROOT):
    subdirs[:] = sorted(d for d in subdirs if d not in DIR_SKIP and not d.startswith('.'))
    for name in sorted(filenames):
        path = Path(directory, name)
        if path.suffix.lower() in TRACK and not name.startswith('.'):
            files.append(path)
for path in sorted(files, key=lambda p:p.relative_to(ROOT).as_posix()):
    relative = path.relative_to(ROOT).as_posix()
    H.update(relative.encode('utf-8') + b'\0')
    try:
        stat = path.stat()
        if path.suffix.lower() in TEXT_SUFFIXES:
            H.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            H.update(f'{stat.st_size}:{stat.st_mtime_ns}'.encode('ascii'))
    except OSError as exc:
        sys.exit(f'SCHOOL_CACHE_PREPARE_STOP cannot inspect {relative}: {exc}')
# Include cache algorithm, omitted from recursive scan to avoid scanning volatile ai/.
for name in ('build_school_cache_variant.py', 'prepare_school_cache.py'):
    path = ROOT / name
    if not path.is_file():
        sys.exit(f'SCHOOL_CACHE_PREPARE_STOP missing {name}')
    H.update(name.encode() + hashlib.sha256(path.read_bytes()).digest())

sig = H.hexdigest()
out_dir = ROOT / 'ai' / 'model'
out_dir.mkdir(parents=True, exist_ok=True)
manifest = out_dir / 'school_cache_manifest_v1.json'
cache = out_dir / 'playable_schools_cache_v1.json'
old_sig = None
if manifest.exists():
    try:
        old_sig = json.loads(manifest.read_text(encoding='utf-8')).get('signature')
    except (OSError, ValueError, TypeError):
        pass
if old_sig != sig and cache.exists():
    cache.unlink()
    print('SCHOOL_CACHE_INVALIDATED source/assets changed')
manifest.write_text(json.dumps({'signature':sig, 'tracked_files':len(files), 'format_version':1}, indent=2), encoding='utf-8')
print(f'SCHOOL_CACHE_MANIFEST_OK tracked_files={len(files)} signature={sig[:14]} cache_present={int(cache.exists())}')
