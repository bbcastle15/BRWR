# Tabletop artwork — 2026-10-03

## assets/tabletop/card_back.png

Use case: stylized-concept. Production asset: one generic face-down card back for a gothic fantasy board game, portrait aspect ratio 2:3. Full-bleed rectangular card, black textured leather and antique ivory and muted gold fine baroque thorn filigree. Elegant thin nested rectangular borders with intricate corners, dark charcoal central field with one centered embossed dark metallic rose medallion. Sophisticated restrained material detail, excellent small size readability. Perfectly flat orthographic scan, symmetry, no perspective, no cast shadows outside card, no text, no letters, no numbers, no specific school identity or player colour. Generic and identical for all hidden cards. Match the muted black/brass style of the playmat reference but composed for an upright portrait card back. No transparency inside card.

Reference: assets/tabletop/playmat.png

Generated with the built-in image_gen tool. Player rim colours are applied at runtime with the existing player_token shader; source alpha is preserved. No card/game state is encoded in these assets.

## assets/tabletop/playmat.png

Use case: stylized-concept. Asset: full-bleed tabletop playmat background for a dark gothic fantasy board game, wide landscape 3:2. Orthographic overhead view, completely flat, no perspective. Elegant extremely dark charcoal and warm black woven neoprene/velvet fabric, fine subtle weave. Faint large faded alchemical concentric circles and botanical thorn/rose tracery integrated into the cloth with very low contrast. Broad quiet central 85 percent area so detailed physical boards laid on top remain readable. Refined thin antique brass embroidered ornamental border confined to outer 3 percent, delicately intricate corner motifs. Expensive tactile tabletop surface, restrained mature art direction, soft uniform light. No cards, no boards, no objects, no people, no text, no logos, no distinct bright symbols, no numbers, no vignette frame outside cloth. The fabric fills the image completely. Rich material detail but no visual noise. High resolution.

## assets/tokens/trap.png

Use case: precise-object-edit. Asset: one trap board game token game sprite. Reference image 1 shows the actual symbols to preserve; reference image 2 is the existing game's purple circular token to match. Produce ONE standalone circular token, perfectly front-facing, centered, occupying 90 percent of a square canvas. Genuine transparent background outside the circle. Thick faceted amethyst-purple gemstone rim, black nearly matte center, crisp raised ivory/silver emblem of an open steel toothed bear trap, jaw opening horizontally, the crisp white metal silhouette shown in the reference left pile. Match reference 2's rim texture and shape. Strictly monochrome white/silver/black interior; only the rim is saturated purple, so runtime can recolor it for each player. Very legible emblem at small game size. Subtle embossed depth, no oblique perspective, no writing, no letters, no numbers, no additional motifs, no multiple coins, no scene, no checkerboard background.

References:
- C:/Users/bigba/AppData/Local/Temp/codex-clipboard-9eceaf54-75aa-4451-8f13-dd18bba430a1.png
- C:/Users/bigba/Desktop/BRWR/brwr/assets/tokens/mage_power.png

## assets/tokens/protection.png

Use case: precise-object-edit. Asset: one protection board game token game sprite. Reference image 1 shows the actual symbols to preserve; reference image 2 is the existing game's purple circular token to match. Produce ONE standalone circular token, perfectly front-facing, centered, occupying 90 percent of a square canvas. Genuine transparent background outside the circle. Thick faceted amethyst-purple gemstone rim, black nearly matte center, crisp raised ivory/silver emblem of a silver medieval shield with a clear double outlined pointed shield shape, matching the shield in the reference left pile. Match reference 2's rim texture and shape. Strictly monochrome white/silver/black interior; only the rim is saturated purple, so runtime can recolor it for each player. Very legible emblem at small game size. Subtle embossed depth, no oblique perspective, no writing, no letters, no numbers, no additional motifs, no multiple coins, no scene, no checkerboard background.

References:
- C:/Users/bigba/AppData/Local/Temp/codex-clipboard-9eceaf54-75aa-4451-8f13-dd18bba430a1.png
- C:/Users/bigba/Desktop/BRWR/brwr/assets/tokens/mage_power.png

## assets/tokens/permanent.png

Final replacement: eight tapered rays matching the Persistence tokens on rulebook page 20. Quick (lightning), I, II and III are rendered from the originating physical spell slot by `TabletopStyle.marker()`. The first capped cross was discarded.

Final symbol reference: `../materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`, page 20, rendered with Poppler to `output/tabletop-shell/persistent-reference.png`. Final raster generated with the built-in image_gen tool, alpha preserved, saved to `assets/tokens/permanent.png`.

Use case: precise-object-edit.
Asset type: transparent PNG game token sprite used with a runtime slot label.
Image 1 is the high-quality purple-rim token edit target. Image 2 is an enlarged direct render of the actual rulebook's four Persistence tokens and is authoritative for the emblem.
Replace the bulky capped double-cross inside image 1 with the exact fine eight silver tapered rays around the center visible on image 2: four cardinal rays and four shorter diagonal rays, a subtle compass-like starburst. Each ray is slender and pointed. Leave a small clean empty black space at the very centre for the game to place I, II, III or a lightning bolt dynamically. The central empty region should be roughly 20 percent of the token diameter. Do NOT draw the roman numerals, bolt, letters or cross in this base image. The eight rays alone must match the reference. Keep the purple faceted outer rim, black textured circular interior, round shape, size and high-quality physical board-game material style from image 1. Front-facing upright, one circle, centered, square canvas, true transparent background outside. Only the rim is saturated purple, all rays ivory-silver. No added bars or decorations.

References:
- C:/Users/bigba/AppData/Local/Temp/codex-clipboard-9eceaf54-75aa-4451-8f13-dd18bba430a1.png
- C:/Users/bigba/Desktop/BRWR/brwr/assets/tokens/mage_power.png


