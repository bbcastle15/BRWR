# Starting School draw — 3 November 2026

The match now opens with a short Library presentation: a shuffled deck, six
cards dealt and flipped in sequence, then a readable overview with School
names. It lasts about 5.6 seconds and closes automatically. Skip animation,
Esc, Space or Enter dismiss it; the button becomes Continue during the final
overview. The existing playmat, card backs, School images and title font are
reused, with the artwork's 2:3 proportions preserved.

`school_draw_presentation.gd` is presentation only. It reads the existing
`active_school_ids` in order; it never selects Schools or consumes Game.rng.
`game.gd` opens it when local/host setup starts. `network_projection.gd` opens
it from the host's public selection during setup, never from a client's
temporary local selection. The finished presentation remains hidden until
the Game is freed, preventing repeated snapshots from replaying it. Joining
an Action-phase match does not show a startup draw.

The full-screen layer blocks table clicks and keyboard shortcuts;
`table_camera.gd` also prevents camera movement while it is active.
`tabletop_shell.gd` keeps other public animation queues pending until the
reveal finishes. No new authoritative state, network choice, rule or deck
ordering was introduced. The first Mage/setup choice remains intact behind
the presentation.

The existing title font was copied to `assets/fonts/library_title.ttf` so it
can be imported/exported; its original production source directory is ignored
by Godot. Original School/card artwork is unchanged.

## Verification

- Godot 4.7.2 import/parser check passed.
- `nov03_school_draw.gd`: 33 assertions passed with native OpenGL rendering.
  Covers real setup entry, card order/art, unchanged RNG and setup choice,
  sequential reveal, automatic closure, mouse blocking, 720p resize, actual
  Skip-button input, Space, first remote snapshot, duplicate snapshots and
  joining an already running match.
- Existing headless checks: 18 Avatar marker, 8 Remote Avatar and 73 UI
  assertions passed. Total for this change: 132 passing assertions.
- `git diff --check` passed. No card JSON was changed.

Visual evidence under `docs/handoff-2026-10-18/evidence/`:
`nov03-school-draw-shuffle.png`, `nov03-school-draw-dealing.png`,
`nov03-school-draw-result.png`, `nov03-school-draw-laptop.png`.

The browser export and `deploy/web_bundle` are updated. Source/export parity
passed for 239 Spell textures, 57 Mage cards, 46 source hashes, the title font
and the multiplayer compatibility version. `tools/check_web_export.gd`, used
by the host launcher, also passed. PCK and gzip use five and four parts of at
most 24 MiB respectively; concatenated SHA-256 hashes match the export.
Evidence: `nov03-school-draw-export-baseline.json` and
`nov03-school-draw-web-bundle.json` in the same evidence directory.

No commit, push or public deployment has been performed. Online checks use
the actual filtered host/client snapshot path, not a full match on two PCs.
