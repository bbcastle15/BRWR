# Possessed: reactive Command backs and tokens — 29 October 2026

The five supplied backs are reconstructed at 1024 × 1536 and used on the
top of the Avatar Hand/Grimoire. Two transparent Protection token PNGs use
the same faceted rim and shield treatment as player tokens; the existing
player-color shader gives them the Avatar's charcoal rim.

## Art mapping

| Command | Moon | Public symbol | Back in assets/avatars/possessed/approved/ |
| --- | --- | --- | --- |
| Energy of the Rose; Revenge of the Thorn | I | Broken heart | command_back_1_protection_damage.png |
| Sap of the Black Rose | II | Broken heart | command_back_2_protection_damage.png |
| Revenge Embodied | II | Lightning | command_back_2_protection_combat.png |
| Explosion of Dark Petals | III | Broken heart | command_back_3_protection_damage.png |
| Dark Hammer | III | Lightning | command_back_3_protection_combat.png |

Tokens: `assets/tokens/avatar_protection_damage.png` and
`assets/tokens/avatar_protection_combat.png` (1254 × 1254, genuine alpha).
All six commands have Protection effects in the supplied material.
Non-reactive commands retain their existing Moon-specific backs.

Generated with the built-in ImageGen tool, preserving the existing restored
Possessed illustration. The second-Moon medallions were refined to a straight
half-disc. Exact prompts, corrections, selected generated sources and final
paths are in `handoff-2026-10-18/evidence/avatar-reaction-art-2026-10-29.json`.
User references are preserved in `evidence/avatar-reaction-references/` under
that same handoff directory. Original player and Avatar assets were preserved.

## Runtime and rules

- `AvatarState.public_data()` publishes only the printed reaction symbol,
  its type and whether the Command limit allows it. The two first-Moon backs
  are indistinguishable in the network projection. A client waits for its
  authoritative snapshot before showing a reaction.
- `AvatarArt` selects backs by Moon and symbol; `AvatarBoard` uses this both
  on the deck and in its inspect window. The separate live token covers the
  printed shield, leaving the Moon and title readable. It disappears when
  the top changes to a non-reactive card, the deck empties or the limit is met.
- `TabletopShell` observes public top changes and uses the existing board
  animation queue. The actual Avatar Board opens and the token settles over
  about 1.8 seconds. Refreshes and duplicate snapshots do not replay it.
  A separate visual node survives board refreshes; closing the animation
  restores the live token and consumes no Command.
- `AvatarRules` still resolves only the reaction section, consumes one Command
  and uses the existing Memories/trigger-window lifecycle. The reveal event
  now reports Protection when that is the section being resolved.
- Corrected Combat targeting: merely affecting an Avatar through a Room does
  not activate the lightning protection. Both existing spell-announcement
  paths are supported. A damage condition is checked again when its turn in
  the trigger window arrives, so damage already prevented by another effect
  does not consume the Avatar card.
- Damage prevention occurs before assignment; Revenge of the Thorn waits
  for actual suffered damage. The card-specific effects remain data driven.

Authority: `../materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`, printed page 38;
`../materials/BRWR_FAQ&errata_2026-01-28_Refers to v1.0_ENG.pdf`, “Target of a
Spell” and “Avatar, Trap/Protection”. These paths are relative to the project
root, not this document. FAQ confirms that reactions cannot exceed the
Action Phase limit (three Apprentice / four Master).

## Verification

- Godot 4.7.2 import/parser completed without script errors.
- `oct29_avatar_reactions.gd`: 99 assertions passed headless and with OpenGL
  rendering. Covers all six mappings, loaded high-quality assets, inspection,
  privacy, both limits, both Combat announcement paths, Room/non-Combat
  exclusions, zero/prevented damage, suppression, immunity, top-only behavior,
  visible timing, cancellation and host/client snapshot deduplication.
- Existing `avatar_rules.gd`: 135 assertions passed, including the six printed
  reactions, damage prevention, retaliation, Trophy, and Command consumption.
- Existing `oct28c_remote_avatar.gd`: 8 assertions passed; preserves the latest
  remote Avatar damage / Hand layering fixes. Total: 242 distinct assertions.
- Rendered proofs: `evidence/oct29-avatar-damage-token.png` and
  `evidence/oct29-avatar-combat-token.png` in the handoff directory.
- Export parity checks now cover the three additional Avatar scripts and all
  seven newly generated assets. Baseline: `evidence/oct29-export-baseline.json`.

Web export regenerated in `output/web` using the existing optimized builder:
maximum texture dimension 1024, lossy quality 0.67. The original HD PNGs remain
unchanged. Final PCK: 94.6 MiB; gzip: 92.1 MiB. Both are below the builder's
95 MiB transfer limit. Package verification passed: 178 Spell textures, 57 Mage
cards, 24 matching source hashes, all five new backs and both tokens loadable.
No commit, push or public deployment. A full game on two physical PCs has not
been run; network checks use real host/client snapshots in Godot.
