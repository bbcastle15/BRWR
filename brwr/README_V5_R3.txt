BRWR AI v5-R3: score-first reward + causal effective spell receipts
==================================================================

PURPOSE
- R3 is a new fork of the existing v5-R2 checkpoint, not a replacement.
- Final reward: +2 win/-1 loss + 0.030*personal final points
  + 0.015*clipped(personal - Black Rose, +/-80)
  + 0.002*clipped(personal - other mage mean, +/-20).
- First episode is baseline calibration only; no optimizer update.
- Subsequent episodes use a baseline estimated from PREVIOUS games.
- Action-specific shaping: +0.005 when a spell produces a concrete change,
  +0.007 when a trap/protection TRIGGERS and produces a concrete change;
  capped at +0.040 per original cast decision. No bonus merely for casting.
- Bonuses are applied to the *original selected cast action's* policy gradient;
  final-score reward still applies to all actions by the player.

WHAT COUNTS AS A CONCRETE EFFECT
- Actual changes to mage/evocation damage, room instability, room activation,
  movement/cell status, powers, jinx/destiny, hand/grimoire/memories,
  quests, trophies, summons/evocations, room state and Vastum.
- Genuine spell damage prevention can count even if no damage was placed.
- No bonus for empty-room damage that changes nothing, or for a Trap/
  Protection that was merely armed and did not produce an effect.
- One success per completed spell resolution, not per individual effect line.
- In rare complicated nested interactions some changes may be causally
  ambiguous. This experiment uses a *conservative observed-state detector*;
  do NOT treat it as a proof of strategic quality or perfect attribution.
- Initial instability shown in the spell banner is excluded from the detector;
  it is not enough for a "successful spell" bonus.

FILES
  start_v5_reward_v3.ps1
  build_v5_r3_effect_receipts.py
  r3_game_effect_methods.gd.inc
  inspect_v5_r3_receipts.py
  ai/python/train_v5_reward_v3.py
  ai/python/v5_reward_v3.py
  ai/python/v5_r3_effect_receipts.py
  ai/python/test_v5_reward_v3.py

INSTALL in BRWR/brwr (retain ai/python folder structure):
  Expand-Archive -Path "$env:USERPROFILE\Downloads\BRWR_AI_v5_R3_score_first_effects.zip" -DestinationPath . -Force

1) ONLY inspect source, run unit tests; NO GAME, NO WEIGHTS UPDATED:
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3.ps1 -PrepareOnly

2) Run ONE controlled episode, KEEP JSONL and receipts for auditing:
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3.ps1 -Games 1 -KeepEpisodes

3) Inspect which spells actually earned shaping:
  & "$env:USERPROFILE\ai-env\Scripts\python.exe" .\inspect_v5_r3_receipts.py

4) Only if step 2 has passed: train a small follow-up batch:
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3.ps1 -Games 5 -KeepEpisodes

REQUIREMENTS & SAFETY
- Must have completed v5-R2 training: ai/model/brwr_policy_v5_reward_v2.pt.
- Do not run concurrently with another trainer. Existing trainer lock files
  are checked (do not manually delete a live lock).
- Game and original checkpoints remain untouched. R3 writes:
  ai/model/brwr_policy_v5_reward_v3.pt
  ai/model/training_history_v5_reward_v3.csv
  ai/datasets/v5_semantic_episode_*.jsonl.r3_receipts.json
  Only AI-generated ai/game_school_cached.gd and ai/ai_policy_school_v5_match.gd
  are instrumented after the original v5 preflight; NO production game.gd edit.
- Preflight verifies original v4/v5 feature and score parity; then R3 game and
  worker syntax. If any check fails, training does not run.
- The episode must include a matching receipts file; missing or misattributed
  effects STOP training rather than silently counting casts as successes.
- No Godot Windows executable was available to test these GDScript additions
  in this environment: start with -Games 1, NEVER launch large batches first.
