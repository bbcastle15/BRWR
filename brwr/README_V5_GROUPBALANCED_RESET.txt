BRWR v5 GROUP-BALANCED RESET (isolated branch)
================================================

WHAT IS FIXED
- Each valid action remains distinct (different spells, paths, cards, targets).
- In action_activation_step, score_i becomes score_i - ln(N_family_i),
  where family = detail.descriptor.kind (or detail.kind = 'finish').
- At equal scores, action families have equal TOTAL probability, irrespective
  of the number of paths or discards generated for one family.
- Selection of the precise variant within a family remains learnable.
- All other request types use the original unmodified candidate softmax.
- The policy-gradient loss uses precisely the same normalized distribution
  as the GDScript worker, and its exploration entropy no longer rewards
  larger candidate families just for their larger size.

WHAT RESET MEANS
- Model starts with a completely new random PyTorch initialization, seed 20261111.
- Optimizer Adam is NEW with empty history (no R3/R3-M/v4/v5 inheritance).
- R3 scenario baseline is NEW and empty; first episode calibrates only.
- Keeps the v5 384-dimensional semantic encoder and the R3 reward formula.
- Keeps existing +0.005 per effective spell, +0.007 per effective reaction,
  and -0.003 for each selected Momentum as a strictly local shaping term.
- Original models/checkpoints/training histories remain UNCHANGED.

FILES
  start_v5_groupbalanced_reset.ps1
  ai/python/train_v5_groupbalanced_reset.py
  ai/python/v5_group_balanced.py
  ai/python/test_v5_group_balanced.py
  ai/ai_native_policy_v5_groupbalanced.gd
  ai/ai_groupbalanced_validation.gd
  build_v5_groupbalanced_worker.py
  generate_v5_groupbalanced_probe.py

INSTALL
Extract ZIP into C:\Users\bigba\Desktop\BRWR\brwr . Existing project
scripts are not overwritten, except files with these new names.
Do not launch this trainer while another Godot AI trainer is running.

PREPARE ONLY: no checkpoint or game writes
  powershell -ExecutionPolicy Bypass -File .\start_v5_groupbalanced_reset.ps1 -PrepareOnly

FIRST REAL TEST: creates entirely new model and runs a calibration episode
  powershell -ExecutionPolicy Bypass -File .\start_v5_groupbalanced_reset.ps1 -Games 1 -KeepEpisodes

EXPECTED MARKERS
  V5GROUP_RESET_CREATED weights=random optimizer=fresh baseline=empty games=0
  GROUP_PROB_PARITY cases=5 ... mismatches=0
  V5GROUP_ACTIONS game=1 action_steps=... selected={...} available_candidates={...}
  V5GROUP_CALIBRATION_ONLY game=1 ...
  V5GROUP_GAME_SAVED 1 ... updated=0 ... checkpoint_games=1

After verifying the 1st game, use -Games 10 to start updates.
DO NOT run other training versions concurrently: they share a generated
v5 worker and exported JSON for the current (not production) episode.

NEW CHECKPOINT
  ai/model/brwr_policy_v5_groupbalanced_reset.pt
NEW HISTORY
  ai/model/training_history_v5_groupbalanced_reset.csv

No existing checkpoint is deleted or reset in place. If the new checkpoint
already exists, the trainer RESUMES it rather than overwriting trained weights.

TESTED HERE
- Python unit tests, negative-feedback gradient, synthetic learnability,
  distribution normalization, source-aligned compiler checks.
- The complete Godot parity test and a full game require the local Windows
  project/Godot and are enforced before the first episode.
