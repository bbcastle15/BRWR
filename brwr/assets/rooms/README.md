# Room artwork

- `<art_id>.png`: destroyed-side tile.
- `rebuilt/<art_id>.png`: rebuilt-side tile, including Black Rose Room.
- `tokens/<art_id>_available.png`: available activation token.
- `tokens/<art_id>_used.png`: exhausted activation token.

Artwork IDs come from `data/rooms.json`. Alternative definitions use their own
`id` for artwork and retain `replaces` as the canonical Lodge/Quest identity.
Tiles use a flat-top hexagon with a
2:sqrt(3) bounding-box ratio and transparent exterior. Token images are
approximately 3:1 and also have transparent exteriors.

`room_art.gd` maps the textures onto the existing hex geometry. `room.gd`
projects `flipped` and `activated_this_turn` into the tile and token images;
the artwork does not own or change game rules. Filling instability alone
does not rebuild a room: the existing cleanup resolution performs the flip.

Generated with the built-in image generation tool from user-supplied
screenshots. Prompt templates are recorded in `generation_manifest.json`;
reference screenshots are preserved in `materials/room_references` at the
repository root. Forge's available token was corrected to retain both
movement/activation sequences.

Alternative Rooms are specified in `alternatives_specs.json`, from Codex
Arcanum pp. 84–99. `alternatives_manifest.json` records each requested asset,
its source page, generated file, prompt when retained, dimensions, alpha and
completion status. All 104 alternative-room PNGs are present: 26 complete sets.
Apocalypse and Room of Rebirth have complete artwork but remain disabled
until their respective Personal Library and Phoenix Familiar modes exist.

The alternative-room integration checks cover both faces of all 24 playable
variants, replacement restrictions, canonical Quest identity, interactive
choices, new Evocation abilities, and network projection. Test scripts and
preview captures are kept outside the project so they are not shipped.
