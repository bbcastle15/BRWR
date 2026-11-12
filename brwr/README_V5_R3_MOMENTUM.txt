BRWR v5-R3-M: fork of CURRENT R3 weights with local Momentum penalty
====================================================================

WHY
- Existing R3 final reward remains unchanged: +2/-1 win/loss,
  +0.030 mage personal points, +0.015 margin vs Black Rose,
  +0.002 peer score margin.
- Existing R3 effective effects bonus remains: +0.005 for actual effect,
  +0.007 trap/protection reaction with actual effect.
- Additional -0.003 applies ONLY to the policy gradient of the selected
  Momentum action, not to all other moves and not to final score.
- No Momentum penalty for preparation discards, resolving effect choices,
  or just because "Momentum" appears in a label.
- Two different fields identify a true selected Momentum action:
  `request_type==action_activation_step`, `detail.descriptor.kind==momentum`
  and `detail.action.type==momentum`. Schema mismatch stops the run.
- Each game logs count of Momentum, number of selections where at least one
  cast candidate was also available, and the summed LOCAL penalty.

FORK/RESUME
- Source: ai/model/brwr_policy_v5_reward_v3.pt (must be stable/not training)
- New independent model: ai/model/brwr_policy_v5_reward_v3_momentum.pt
- New independent history: ai/model/training_history_v5_reward_v3_momentum.csv
- Inherits current R3 model weights, Adam optimizer moments AND historical
  scenario-dependent baseline. Since terminal reward is unchanged, there is
  no need to discard learned baseline or spend an episode on calibration.
- Fork happens once on FIRST actual run; future runs resume M checkpoint.
- Original R3 model/checkpoint/history untouched.
- R3-M checks R3 lock at startup: never run both trainers simultaneously.
- R3 parent SHA checked before and after training run; no source modifications.

INSTALL in BRWR/brwr, after the R3 run has stopped safely:
  Expand-Archive -Path "$env:USERPROFILE\Downloads\BRWR_AI_v5_R3_Momentum_Experimental.zip" -DestinationPath . -Force

NO-WRITES PREPARE (can be done while R3 trains):
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3_momentum.ps1 -PrepareOnly

FIRST 1 GAME (ONLY when R3 has completed and the lock is gone):
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3_momentum.ps1 -Games 1 -KeepEpisodes

MORE TRAINING (only after first episode verified):
  powershell -ExecutionPolicy Bypass -File .\start_v5_reward_v3_momentum.ps1 -Games 100

NOTE
- Godot's Windows executable cannot be run here. Python tests and offline
  inspection of an earlier full episode are available; actual first run and
  worker syntax parity are tested by on-device preflight.
- A new branch is an experimental change, not evidence that Momentum is bad.
- Do not manually delete live training lock files.
- Do not use both R3 and R3-M at once: native worker/export files are shared.
