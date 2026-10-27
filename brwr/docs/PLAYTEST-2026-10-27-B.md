# Playtest — 27 October 2026, second revision

Scope: latest 25-point feedback, superseding the previous damage-confirmation and Log behavior.

## Changes

- English game/menu/confirmation/network messages. Study keeps Undo, Clear and Confirm above the cards; the cards fit vertically, including Inspect. Informational prompts are suppressed when there is no pending effect choice; spectators see who is choosing.
- Bartholomäus mage portrait replaced with the masked blue/gold character from Arcane Bond, preserving card values, action slots and format.
- Spell and Room presentations wait for every human, with a ten-second timeout. Damage receipts offer only the viewing player's Continue, including the attacker; they do not display other players' acknowledgements.
- Normal Avatar activation waits two seconds. Resolution pauses for placements, motion, attacks, damage and Power animation. Summon placement is slightly faster; movement and attacks are slower. Client snapshots carry deduplicated attack animation events.
- Damage conversions animate the outgoing owner cube and incoming owner cube. Room instability conversions do likewise, including clients. Black Rose placements are queued before later effects/cards. Positive player Power changes use the Power Board zoom.
- Instability centers are specific to each of the 45 room artworks in `data/room_art_sockets.json`, rather than one generic layout. Evocation inspection includes its assigned Upgrade image.
- Damaging Evocation target selection excludes the caster's controlled Evocations. Athanor Eruption and Deadly Bolt are covered. Existing room-target selection remains a single room choice.
- Active card side has a thicker gold border and glow. Avatar command deck shows a protection marker for its top reactive Command.
- Log is a previous/next card gallery with effect descriptions and targets, physical actions, Room activations, Evocation/final Room entries, triggered Trap context and Avatar actions.
- Nigredo: reproduced successful conversion through host/client snapshots. Player 1's spectator prompt now clears after Player 2 resolves. The reported engine hang was not reproduced; this is not a claim to have diagnosed every possible stuck online state.

## Rule reference

Local `materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`, printed page 38: a Trap/Protection icon on the top Command back identifies an active reaction. The existing reaction engine reveals/resolves that Command when its trigger occurs. The added board marker reflects this public top-card information; it does not expose a hidden face.

## Verification

- `checks/oct27_ui.gd`: 19 assertions, including friendly targets, animation barrier, damage acknowledgement, ten-second timeout, Study, Upgrade and gallery. Rendered screenshots in `docs/handoff-2026-10-18/evidence/oct27-*.png`; Study and room cube centers visually inspected.
- `checks/oct27_network.gd`: 11 assertions, Nigredo host/client resolution, authenticated individual acknowledgement and conversion deduplication.
- `checks/oct27_pacing.gd`: 9 assertions, reactive marker, two-second Avatar delay, visible attack duration and client attack deduplication.
- Existing `checks/oct26_rules.gd`: 13 assertions; `checks/target_selection.gd`: 14 assertions. Total: 66 focused checks passed.
- Local optimized Web export in `output/web`; source/pack parity verifies 172 available Spell textures, 57 Mage cards and 19 source/data hashes. No publication performed.

The catalog still contains 111 Spell definitions without artwork, already absent in the source; export parity checks that the build does not introduce missing assets. This task does not claim to complete those unrelated cards. Online tests simulate host/client snapshots and authenticated messages; no full match on two separate computers was performed.

## Image provenance

ImageGen edited `assets/mages/bartholomaus.png`, using the previous Mage card and `assets/spells/arcane_bond.png`. Generated file: `C:/Users/bigba/.codex/generated_images/01a15366-4fbe-77e1-a417-7b1c320ab75a/exec-3d8a7178-ef9b-4670-a241-8355e0a9b61f.png`.

Prompt: Edit the FIRST landscape mage card. Preserve exact landscape dimensions/aspect, title BARTHOLOMÄUS, all five stat icons and values 10,8,2,2,2, trophy icon and two physical action square slots at their current positions, frame and quality. Replace ONLY the bearded wizard portrait with the very same masked mage depicted on SECOND reference Arcane Bond: elongated sculpted gold full face mask, dark hollow eyes, blue hood edged silver, blue and gold patterned robes, skull pendant with white cloth tassel. No human face or beard. Character appearance must match that reference closely. Keep artwork unobscured and stats readable. High quality finished boardgame mage card PNG. No UI, no background outside card.
