# Player board and evocation artwork

Created with the built-in imagegen tool, 2026-10-01. The source documents are in
`materials/` at the repository root. These images are presentation assets;
gameplay values continue to come from runtime state and the existing databases.

## References and output

| Output | Reference |
| --- | --- |
| `assets/player_boards/mage_sheet.png` | Rebirth rulebook v1.2, page 23, Mage Sheet detail |
| `assets/evocations/nigredo.png` | Codex Arcanum, PDF page 102 |
| `assets/evocations/succubus.png` | Codex Arcanum, PDF page 103 |
| `assets/evocations/cadaver.png` | Codex Arcanum, PDF page 106 |
| `assets/evocations/colossus.png` | Codex Arcanum, PDF page 106 |

The screenshots in `assets/mages/` remain unchanged. Rikkart uses an AtlasTexture
region of `screen_3.png`. Individual `assets/mages/<mage_id>.png` files take
precedence. A mage without an image retains a name/stat placeholder.

## Generation prompt set

Sheet: faithful high-resolution restoration of the Mage Sheet reference,
straight-on 1.2:1 rectangle, transparent rounded corners. Preserve black rose,
smoky charcoal background, silver thorn slot outlines, dark red edging. Remove
turquoise annotation circles, letters, arrow and dashed guide. Empty top damage
track; Quick upper left; landscape Mage upper right; three portrait spells
I/II/III below; external Quest/deck edge markers; one/two/three bottom diamond
markers. No cards, tokens, cubes, added interface or labels. The generated sockets
are decorative; the functional damage track uses MageState.health.

Cards: restore each referenced card in high resolution, landscape 3:2, isolated
rounded corners with transparency, portrait at left third, parchment at right,
silver thorn border. Preserve original arrangement and clear serif typography.
Draw the reference icons rather than writing their descriptions. Exact content:

- **Nigredo / Construct**: Each time the Nigredo inflicts [broken heart], its
  controller may place 1[instability] or convert 1[instability] in a [hexagon 0]
  from it. Movement 2, Strength 2, Health 4.
- **Succubus / Demon**: Has [strength]+1 for each [broken heart] on this Card.
  Each time the Succubus owner suffers [broken heart], the Succubus can suffer
  1[broken heart] of those [broken heart] in their place.
  Movement 2, Strength 1*, Health 3.
- **Cadaver / Undead**: If the Cadaver has an assigned Upgrade, it has [heart]+1.
  Flavor: Even scraps can have their own dignity if used wisely...
  Movement 2, Strength 2, Health 2.
- **Colossus / Undead**: The Colossus inflicts 3[broken heart] to each Mage that
  enters the Room it is in. Flavor: An unnatural abomination, created only to
  spread death. Movement 2, Strength 3, Health 4.

All four cards were visually checked against their source text and printed stats.
Live health, damage, movement, attack and controller are also shown in inspection.

## Player colour variants

`mage_sheet.png` remains the white-player original. Built-in imagegen edits add
`mage_sheet_red.png`, `mage_sheet_blue.png`, `mage_sheet_green.png`,
`mage_sheet_purple.png` and `mage_sheet_yellow.png` in this directory. Each uses
the original sheet as its edit reference, retaining its layout while changing
the smoke and petal highlights. Exact prompts are saved in `color_prompts.json`.
PlayerBoard selects the texture from `PlayerState.color`; card and token colours
are not multiplied by a tint on the whole board.
