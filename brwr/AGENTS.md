# AGENTS.md — Black Rose War Rebirth

## Project

Digital/local adaptation of **Black Rose Wars: Rebirth** built with **Godot 4.7.2**.

Goals:
- reproduce the tabletop rules faithfully;
- support 2–6 local/hot-seat players;
- implement base game first, then expansions;
- later support AI players;
- preserve a tabletop-like presentation.

The current repository is authoritative. This file contains project guidance and historical context, not a replacement for inspecting the code.

---

## Mandatory workflow

Before editing:

1. Inspect the relevant current files.
2. Search all references to classes, signals, node paths, IDs, resources, and data fields involved.
3. Inspect `git status` and, when relevant, `git diff`.
4. Determine which implementation is actually used at runtime before changing duplicated-looking code.
5. Prefer extending existing systems over creating parallel ones.

While editing:

- Make the smallest coherent change.
- Preserve working behavior unrelated to the task.
- Do not perform speculative refactors.
- Do not create duplicate sources of game state.
- Do not edit backup/temp files unless explicitly requested.
- Do not invent board-game rules or card effects.

After editing:

1. inspect `git diff`;
2. check GDScript parser/type errors;
3. validate JSON when modified;
4. run existing tests or Godot checks when possible;
5. report exactly what was tested and what remains unverified.

Do **not** automatically create a Git commit unless explicitly asked.

---

## Godot / GDScript

Target: **Godot 4.7.2**.

Use Godot 4 syntax only.

Prefer:
- the conventions already present in the repository;
- typed variables where consistent with nearby code;
- signals / refresh methods for UI updates;
- authoritative runtime state outside purely visual nodes.

Avoid:
- Godot 3 syntax;
- new autoloads unless clearly necessary;
- brittle hard-coded scene paths when existing references can be reused;
- storing authoritative game state only inside UI controls.

The UI should normally be a projection of game state.

Preferred direction:

```text
JSON / Database
      ↓
Runtime State
      ↓
Game logic / Effect resolvers
      ↓
Signals / refresh
      ↓
Boards / HUD / Card views
```

Avoid:

```text
UI local state
      ↓
game logic
```

---

## Important project files

The repository may evolve. Search before assuming these names are still exact.

Core files have included:

- `game.gd`
- `beta_hud.gd`
- `player_board.gd`
- `active_spell_state.gd`
- `card_state.gd`
- `card_view.gd`
- `cell.gd`
- `cube.gd`
- `effect_resolver.gd`
- `event_board.gd`
- `event_card_state.gd`
- `event_database.gd`
- `event_effect_resolver.gd`
- `evocation_database.gd`
- `evocation_state.gd`
- `game_event.gd`
- `mage_database.gd`
- `mage_state.gd`
- `black_rose_room.gd`

Data files include:

- `cells.json`
- `events.json`
- `evocations.json`
- `layouts.json`
- `mages.json`
- `quests.json`
- `rooms.json`
- `spells.json`

Never create a second database/state model simply because an existing one is inconvenient.

---

## Lodge and board layout

The Lodge and side boards have already undergone manual visual tuning.

Known intent:
- room DB: 19 rooms;
- random room pool: 17;
- layouts support 2–6 players;
- 2P and 4P layouts were considered correct;
- 3P requires special slot placement;
- 5P/6P were manually corrected after visual testing.

Do not casually rewrite Lodge geometry or player-count layouts.

### Power Board

Already implemented and tuned.

Important intent:
- interlocks with Lodge;
- Power Track runs 0–35;
- Moon thresholds at 6 / 18 / 30;
- four card slots:
  - Quest
  - Jinx
  - Evocation
  - Upgrade

Historical numeric geometry values are not authoritative; current code is.

### Event Board

Already designed to interlock with the Lodge.

Keep its geometry unless the task is explicitly about it.

---

## Player Boards

Each active player has a Player Board.

Typical information:
- player;
- mage;
- HP;
- Power;
- cubes;
- hand;
- spell slots I–IV.

General table layout intent:

```text
P1                              P2

P3    EventBoard - Lodge - PowerBoard    P4

P5                              P6
```

Only boards for active players should be visible.

A prior issue caused Player Boards to hide/overlap the Lodge. Preserve the existing fix unless explicitly redesigning layout behavior.

---

## Cubes

Known pool intent:
- 25 cubes per player;
- 30 Black Rose cubes.

State must be authoritative outside visual cube nodes.

---

## Cards and data

Card definitions should remain data-driven where practical.

Before writing a card-specific special case:

1. check whether the existing effect resolver already supports the mechanic;
2. check whether the JSON schema can express it;
3. add a custom handler only when genuinely necessary.

Do not build large chains of `if card_id == ...` for mechanics that can be generalized.

For card images:
- do not rename files casually;
- search all references before changing paths;
- preserve aspect ratio;
- reuse the existing card/card-view system where practical.

---

## Hot-seat privacy

This is local multiplayer with private information.

Examples:
- hand cards;
- set/prepared spells;
- potentially hidden Quest information.

Rules:
- full private information is inspectable only by the appropriate viewer;
- non-owners should see a card back / hidden placeholder / count as appropriate;
- when game rules make information public, every player may inspect it;
- do not delete private data from shared state just to hide it from UI;
- visibility should be a rendering/access decision based on authoritative state.

---

## Spells

Relevant concepts may include:
- spell definition;
- card state;
- active spell state;
- set/prepared state;
- reveal/play state;
- resolution;
- discard/removal;
- card view;
- PlayerBoard spell slots;
- HUD spell rendering.

Before modifying spell behavior, map the complete lifecycle and identify where ownership, preparation, reveal, resolution and rendering are currently stored.

Do not create a second independent spell-state model.

---

## CURRENT PRIORITY — prepared spells on PlayerBoard

This is the immediate development task.

Desired behavior:

1. Cards set during Preparation are represented physically on the corresponding `PlayerBoard`.
2. A set/prepared spell is private.
3. Before play/reveal:
   - its owner can inspect the full card;
   - other players cannot inspect its contents.
4. Non-owners may still see that the spell slot is occupied.
5. Once the spell is played/revealed:
   - every player may inspect the card.
6. Existing Preparation logic must continue working.
7. Existing spell resolution must continue working.
8. Reuse the existing Card/CardView infrastructure where possible.
9. Visibility should derive from authoritative spell/card state, not duplicated arbitrary UI flags.

A previous automated patch attempt reported:

```text
ERROR: PlayerBoard Spell renderer: expected 1 match, found 2
```

Therefore the repository may currently contain partial changes or duplicate matching renderer code.

### Before implementing anything else

Inspect:

- `git status`
- `git diff`
- `player_board.gd`
- `game.gd`
- `beta_hud.gd`
- spell/card state classes
- existing card rendering / click-to-inspect code

Specifically:

1. identify the two renderer-like sections in `player_board.gd`;
2. determine which is used and whether one is stale/duplicate;
3. determine whether the failed patch left partial changes;
4. inspect whether `game.gd`, `beta_hud.gd`, and `player_board.gd` currently render the same spell information through overlapping paths;
5. consolidate rather than blindly patching every match.

Map this lifecycle before editing:

```text
spell selected
→ spell set during Preparation
→ stored in authoritative player/card state
→ rendered in PlayerBoard slot
→ privately inspectable by owner
→ played/revealed
→ publicly inspectable
→ resolved
→ discarded/removed as required
```

Do not change game rules while implementing the UI.

---

## Player position tokens

Players need simple tokens on the Lodge.

Requirements:
- token identifies the owning player clearly;
- token position comes from authoritative player room/cell state;
- movement updates rendering;
- token node is not the source of truth for location.

Keep the visual simple unless assets already exist.

---

## Evocation tokens

Evocations also need simple Lodge tokens.

Each token must make clear:
- which evocation it represents;
- which player owns/controls it.

Ownership/location must come from `EvocationState` or the current equivalent runtime state.

Do not store ownership/location only in the visual node.

---

## Quests

A Quest system already exists and basic tests passed.

Known validated behavior:

### Shattered Illusion

Expected lifecycle:

```text
revealed=false
progress=0
→ valid trigger reveals quest and progresses it
→ irrelevant effect ignored
→ second valid trigger completes quest
```

### Holy Corruption

Used to validate a Quest that completes without the standard numeric/cube progress lifecycle.

Therefore:
- do not assume every Quest has numeric progression;
- preserve data-driven quest behavior.

There was also a correction involving a duplicate/incorrect `Contingent Mage` entry. Inspect current `quests.json`; do not reconstruct old assumptions from memory.

---

## Events / Moon phases

Event systems already exist, but card content for every Moon phase may still be incomplete.

Keep these concerns separate:
- Event data;
- Event card state;
- Event effect resolution;
- Event Board rendering.

Do not treat missing content as an engine bug.

---

## Debugging rules

When a bug appears:

1. reproduce or identify the failing path;
2. identify the authoritative state involved;
3. determine where the state should be consumed/rendered;
4. inspect signal/refresh flow;
5. fix the smallest coherent layer;
6. verify a second legacy path is not still active.

Prefer root-cause fixes to UI workarounds.

If an automated replacement reports something like:

```text
expected 1 match, found 2
```

stop and inspect both matches.

Never silently modify the first match.

---

## JSON validation

When changing JSON:

- ensure valid syntax;
- preserve stable IDs where already used;
- ensure IDs are unique;
- ensure referenced IDs exist;
- ensure resource/image paths exist;
- do not silently change schema without updating all consumers.

---

## Testing and reporting

After a coding task, summarize:

- files changed;
- behavior changed;
- important architectural choice;
- tests/checks actually run;
- anything still unverified.

Do not claim Godot runtime success if Godot was not actually run.

Do not dump every changed line unless asked.

---

## Rule authority

When information conflicts, use this priority:

```text
direct user instruction
> physical game rules / card data supplied by the user
> current repository implementation
> historical notes in AGENTS.md
```

If a meaningful conflict is discovered, report it rather than silently guessing.
