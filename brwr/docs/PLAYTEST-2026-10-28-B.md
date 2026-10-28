# Playtest — 28 October 2026, second revision

Latest scope: Study selection glitch, choices in history, attack wind-up/contact/recoil, 10% shorter animation gaps, unclosable defeated board in Web, Trophy placement.

## Changes

- Study updates the existing gallery instead of rebuilding/refitting it after every draw. Selection borders preserve content margins. The draft separator uses the same font metrics as the initial text, avoiding a one-pixel layout shift.
- Accepted effect choices record the selected target/options and the resolving effect in the shared history. Study and Preparation choices have separate entries; hidden card identities remain private. Rejected submissions are not recorded.
- Attack animation: 0.14-second wind-up, 0.36-second approach, contact at half the standard token diameter, small target recoil, brief impact hold and return. The original attacker stays hidden while its visual copy moves.
- Inter-animation gaps changed from 1.0 to 0.9 seconds, including movement, physical-token observation, world placements and Power. Confirmation limits and Avatar's turn delay are unchanged.
- Damage receipt Close/Escape acts as Continue. Online clients hide their own board after acknowledging; they do not remain looking at the defeated board while peers confirm. Damage confirmations now expire after 10 seconds measured from completion of the host animation. Cancellation clears stale receipt/ghost state.
- A newly earned Trophy is animated onto the enlarged PlayerBoard or Avatar Board; cleanup restores the actual token and removes the temporary copy.

## Verification

80 assertions passed:

- `oct28b_feedback.gd`: 23, with rendering enabled. Study identity/geometry stable across selections, Undo/Clear, history privacy and rejection, resolving-effect/target logging, Trophy on ordinary and Avatar boards, receipt timeout, attack wind-up/contact/recoil/restoration.
- `oct28_full_defeat.gd`: 3, actual lethal Avatar damage through the engine, defeat resolution and board release.
- `oct28_defeat.gd`: 12, host snapshots applied to two simulated clients, including an open Hand and individual acknowledgements.
- `oct28_sequence.gd`: 28, Explore pacing, Quest confirmation, attack source restoration and room slots.
- `oct28_ui.gd`: 14, short canvas Study layout, kept-card confirmation, outline-only frame, room slots and effect prompts.

The reported browser-session freeze was not reproduced directly. These are native Godot rendering/engine and snapshot tests, not a completed multi-browser match. The Web confirmation changes address unclosable local receipts and indefinite peer waits; actual browser play remains to be checked.

Local Web export rebuilt in `output/web`: `index.pck` 99,482,028 bytes; gzip 96,770,112 bytes. Export parity PASS: 178 available Spell textures, 57 Mage cards and 21 matching script/data hashes. This confirms the new scripts are in the pack; it does not constitute browser-session validation. No online publication or Git commit performed.

The sandbox prevented default user-log/shader-cache writes in some native runs. Explicit workspace test logs were used for the rendered and final full-defeat checks; no script/parser errors were reported.
