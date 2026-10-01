# Room artwork

- `<room_id>.png`: existing destroyed-side tile (unchanged).
- `rebuilt/<room_id>.png`: rebuilt-side tile, including Black Rose Room.
- `tokens/<room_id>_available.png`: available activation token.
- `tokens/<room_id>_used.png`: exhausted activation token.

Room IDs come from `data/rooms.json`. Tiles use a flat-top hexagon with a
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

Validation scripts:

- `room_art_playtest.gd`: texture coverage, state transitions, existing rules.
- `room_rebuilt_preview.gd`: renders all rebuilt rooms with available and used
  tokens to `output/rooms-rebuilt-available.png` and `output/rooms-rebuilt-used.png`.
