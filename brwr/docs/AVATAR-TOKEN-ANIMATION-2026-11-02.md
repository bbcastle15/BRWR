# Avatar token placement — 2 November 2026

The reported missing Protection/Trap animation was reproducible even though
the isolated placement-preview checks passed. Before the fix, three assertions
failed in `nov02_avatar_marker_playtest.gd`:

- The resolver observed a new reactive top card and queued its marker, then the
  UI observed a changed viewer and cleared the queue when closing the board.
- A new choice request likewise cleared an unplayed marker presentation.
- The first remote snapshot treated the current token as already presented.

`tabletop_shell.gd` now retains queued Avatar placements through ordinary
interface transitions. An interrupted placement is retained once and resumes
after the intervening card/choice. Explicit Close, Esc, or Lodge navigation
can skip the active presentation without a replay loop. Finishing the animation
restores any pending authoritative choice. Only public presentation records are
retained; no card identity, game state, or Command count is duplicated.

`network_projection.gd` requests one presentation of the current public Avatar
token on the first snapshot. Subsequent identical snapshots do not repeat it;
historical damage and other feedback are still not replayed on entry.

`assets/tokens/player_token.gdshader` now respects CanvasItem opacity/tint.
Previously its final fragment colour replaced the opacity animated by the UI,
so the token's fade-in did not actually appear in the rendered pixels.

The existing ~1.8-second placement opens the actual Avatar Board. Damage and
Combat shields retain their existing distinct artwork. The generic Trap path
uses the existing Trap asset. No Possessed cards, effects, triggers, or Command
limits were changed or invented; the Trap check uses a synthetic public UI
projection only.

## Verification

Godot 4.7.2 was run with native OpenGL rendering:

- `nov02_avatar_marker_playtest.gd`: **19 assertions passed**, including both
  interruption paths, resumption, explicit dismissal, first online snapshot,
  duplicate snapshots, Trap rendering, Command limit, both Protection glyphs,
  completion and four checks of actual rendered shader opacity.
- `oct29_avatar_reactions.gd`: **99 assertions passed**.
- `nov01_playtest.gd`: **73 assertions passed**.
- `oct28c_remote_avatar.gd`: **8 assertions passed**.
- **199 distinct assertions**, clean runtime logs and `git diff --check`.

The older explicit-close test now calls the same skip path as the actual Close
button. Test fixture cleanup explicitly clears presentation queues rather than
mistaking a normal interface transition for a reset.

Rendered evidence:
`docs/handoff-2026-10-18/evidence/nov02-avatar-protection-placement.png` and
`nov02-avatar-combat-placement.png`.

No complete game between two physical PCs was run; multiplayer tests exercise
the real filtered host/client snapshots.

## Deliverables

Updated `output/web` with the existing optimized exporter (1024 / 0.67), without
altering the original artwork. Package parity passed for **184 Spell textures,
57 Mage cards and 32 source hashes**, including the modified token shader.
The existing Avatar backs/tokens and Hex completeness check also pass.
Baseline: `docs/handoff-2026-10-18/evidence/nov02-export-baseline.json`.

Final PCK: **95.16 MiB**, gzip **92.60 MiB**. The current Render deployment
reconstructs `deploy/web_bundle/*.partNNN`, so that bundle was also updated.
Both PCK files keep four parts, now at most **24 MiB** each, with no obsolete
tail. SHA-256 of each concatenated bundle was checked against `output/web`.
Other Web runtime files were copied from the same verified export.

No commit, push or public deployment was performed. Publish the updated bundle
through the existing workflow to apply this fix to the hosted browser version.
