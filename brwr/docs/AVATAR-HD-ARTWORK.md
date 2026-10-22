# Avatar card reconstruction

## Current status — 21 October 2026

Runtime prioritizes `assets/avatars/possessed/approved/`: 30 Command faces, 15 Event faces and Possessed. These are restored PNGs based on the Energy of the Rose approach accepted by the user, with subsequent symbol corrections. The old atlas is only a fallback; the 46 expected faces are present. The folder name identifies the accepted approach, not individual user approval of every generated image.

Actual Godot captures: `handoff-2026-10-18/evidence/avatar-fourth-board.png`, `avatar-fourth-possessed.png`, `avatar-fourth-avatar_divinatory_secrets.png`, `avatar-fourth-possessed_frost_spear.png`. Board and Frost Spear captures visually checked. Other symbol details still merit review; do not claim pixel-identical restoration. Existing exported executables have not been rebuilt.

The following historical sections are superseded by this status.

## Historical status — third playtest: superseded

The user requires the same original cards, with improved scan quality only.
The typeset `production/` faces and earlier reinterpretations are rejected.
New ImageGen restoration trials also changed pictograms (e.g. Book of Nature
and Revenge of the Thorn). They are **not approved for runtime**; `faithful/`
is ignored by Godot. Its name describes the attempted goal, not the result.

`AvatarArt` now uses the unmodified source atlas for all 46 faces, including
Possessed. The three restored Moon backs remain. This removes the invented
frames, but **does not complete HD restoration**. Source-resolution faces
must not be described as publication-ready. Faithful HD still needs a better
source or a restoration method that passes symbol-by-symbol visual comparison.

The following describes superseded work, retained for provenance only.

## Superseded production assets — second playtest

Runtime first loads `production/`: 30 Command faces and 15 Event faces at
1536×2304, plus the native vector `board.svg`. Generator:
`tools/build_avatar_production.py`. It extracts the actual BRWR symbols from
the supplied rulebook's embedded font, preserving shapes and distinguishing
Damage (E902) from Instability (E904). Room glyph mapping comes from page 25.
The faces are native typography/vector composition, not enlarged screenshots
or generative lettering. Their ornamental frame is reconstructed rather than
a pixel-identical reproduction of the printed border. The generator rejects
overflow and uses fallback letters where PDF font subsets omit outlines.
High-resolution wood and parchment illustrations are separate background
materials; their built-in ImageGen prompts are in `material_provenance.json`.
The runtime board combines a clipped material polygon with the sharp SVG
recesses/borders and native Godot health numbers; no screenshot enters it.

Restored card backs for Moon 1/2/3 are `restored/command_back_1.png` through
`_3.png`; built-in ImageGen prompts and provenance are recorded in
`production/raster_provenance.json`, along with the localized Raging Lash edit.
Possessed still uses the restored character image. Original references remain
unchanged. Intermediate fonts in `production/source_fonts/` are ignored by
Godot; only the finished PNG/vector assets are used at runtime.

Later sections describe superseded attempts, not the current runtime choice.

## Current restoration, superseding the redesign below

The user rejected the teal redesign for Events and Possessed. Runtime now
prefers the 16 restored originals in `assets/avatars/possessed/restored/`.
The original sheets and character image are preserved. Restoration uses the
built-in ImageGen tool with the original sheet as the authoritative reference;
localized corrections use the restored card as the edit target. Exact prompts,
reference sheets and generation provenance are in `restored/provenance.json`;
subsequent localized edits are recorded in `restored/corrections.json`.
Output aspect ratios vary slightly, with a short edge of at least 1000 pixels.

Generated restoration is not a lossless reconstruction of unreadable detail.
Visual fidelity, small print and icon shapes require separate review; the
automated loading/resolution check does not certify them. The previous design
and generator below remain historical, and are still used for Commands/back.

47 cards rebuilt: 30 Commands, 15 Events, Possessed and Command back.
Portrait cards: 1024 × 1536; Possessed: 1536 × 1024.
Original screenshots remain unchanged in `assets/avatars/possessed/`.
Runtime prefers the new files in `assets/avatars/possessed/hd/`.

The built-in ImageGen tool produced the new blank card frame and the
Possessed illustration. Card text is typeset separately using Georgia and
ReportLab, then rendered with PDFium. Text does not come from screenshot
scaling, OCR or generative lettering. `tools/build_avatar_cards.py` recreates
all 47 PNG files and a multipage proof PDF in the handoff evidence folder.
The generator fails if a text block does not fit. English rules are transcribed
from the supplied screenshots and the authoritative command/event JSON.
Book of Nature's grey destination was corrected against `commands_1.png`.
Dark Blade uses Priority 1 per Codex errata, rather than the printed 3.

## Built-in generation prompt set

Card template:

> Create one premium board-game card template, portrait 2:3 aspect ratio, high resolution. Style Black Rose Wars Rebirth: ornate dark petrol teal carved black floral thorns frame, narrow aged gold decorative rules, warm ivory parchment center subtle faded arcane compass engraving. TOP 20 percent dark teal floral header for later title typesetting, central 65 percent blank light parchment for exact rules text to be added later, bottom 15 percent parchment footer divided by fine gold horizontal rule. No letters, no numbers, no words, no icons, no mockup, flat orthographic print asset, fully fills image. Elegant polished detailed frame coherent with the provided game's Black Thorns card. Must be crisply defined, parchment not wrinkled or obscured, very high readability of blank central area.

Possessed illustration:

> Use the attached Possessed card as character design reference only, not as an edit target. Create a NEW high-definition dark fantasy illustration of Possessed, the enslaved mage of the Black Rose: solitary hooded mage, full torso, face concealed in black hood, scorched black tattered robes and layered worn armor, thorny black rose vines binding his arms and chest, faint pale moon behind his head, sinister desolate gothic lodge mist background, muted petrol teal / charcoal / aged gold palette, premium Black Rose Wars board-game painted art, detailed and cinematic yet restrained. Portrait image. No text, no frame, no symbols, no statistics. Distinct and readable silhouette, avoid bright cartoon color.

Both generated source images are kept beside the rendered cards. The source
screenshots and gameplay data are preserved. No web export was generated.
