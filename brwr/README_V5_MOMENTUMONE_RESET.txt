BLACK ROSE WARS REBIRTH — V5 MOMENTUM-ONE RESET
================================================

WHAT CHANGES (AI only)
- All Momentum variants (movement direction, discarded card, etc.) together
  count as ONE virtual choice at the first stage of action_activation_step.
- Each legal Cast candidate counts as its own virtual choice.
- Other categories (Explore, Fight, Quest, Finish, ...) retain one virtual
  slot per family, as in the previous V5 group-balanced branch. This prevents
  a large Explore path list from drowning every other action.
- A category's first-stage logit is the MEAN of its candidate logits. After
  selecting it, the exact legal variant is sampled by a conditional softmax.
- The PyTorch loss/gradients use exactly the same hierarchical probabilities
  as the generated Godot worker. Entropy regularization follows virtual
  first-stage choices, not the number of Momentum variants.
- NON-action choices (preparation, discard, effect resolution, etc.) remain
  standard unmodified softmax. R3 reward shaping remains unchanged.

SIMPLE EXAMPLE (equal neural scores, only these actions available)
  21 Momentum variants + 2 different Cast candidates:
  NEW: 1 virtual Momentum + 2 virtual Casts
       P(Momentum total) = 33.33%  | P(Cast total) = 66.67%.
  OLD V5 group-balanced: P(Momentum total)=50%, P(Cast total)=50%.

This is NOT a hard-coded ban or fixed penalty. As learning changes scores,
probabilities can change. The model may still choose Momentum when useful.

INSTALLATION
Extract the CONTENTS of this ZIP into:
  C:\Users\bigba\Desktop\BRWR\brwr\
The ZIP contains NEW filenames only; it does not overwrite the original
Game scripts, the old V5 group-balanced policy, or previous trainers.
The existing optimized V5 + R3 files must already be present (they are
required by the V5-GROUP-RESET that is already installed).
Do not train two BRWR policies at the same time: the generated AI-only worker
and exported temporary native policy weights are shared by trainers.

COMMANDS (PowerShell from C:\Users\bigba\Desktop\BRWR\brwr)
  powershell -ExecutionPolicy Bypass -File .\start_v5_momentumone_reset.ps1 -PrepareOnly

  powershell -ExecutionPolicy Bypass -File .\start_v5_momentumone_reset.ps1 -Games 1 -KeepEpisodes

If tests and one calibration episode are successful, RESUME:
  powershell -ExecutionPolicy Bypass -File .\start_v5_momentumone_reset.ps1 -Games 10 -KeepEpisodes

EXPECTED OUTPUT
  13 new Python tests + 9 R3 momentum + 5 R3 reward tests = 27 tests.
  V5M1_PREPARE_OK tests=pass writes=0 games=0 ... (first command)
  V5M1_RESET_CREATED weights=random optimizer=fresh baseline=empty games=0 ...
  V5M1_RESUME_OK games=0 ...
  V5M1_WORKER_OK source_worker_only=1 one_momentum_slot=1 ...
  MOMENTUM_ONE_PROBE_OK cases=7
  MOMENTUM_ONE_PARITY cases=7 ... mismatches=0
  V5M1_REAL_PROBS game=1 both=... mean_p_momentum=... mean_p_cast=...
  V5M1_CALIBRATION_ONLY game=1 no_gradient=1 ...
  V5M1_GAME_SAVED 1 ... updated=0 ... checkpoint_games=1
  V5M1_TRAIN_COMPLETE from=0 to=1 previous_models_unchanged=1

RESET / CHECKPOINT ISOLATION
New training starts at ZERO games, with new random network seed 20261112,
new optimizer, empty R3 baseline. It does NOT resume the old group-balanced
checkpoint (which had one calibration game). The new branch uses:
  ai/model/brwr_policy_v5_momentumone_reset.pt
  ai/model/training_history_v5_momentumone_reset.csv
  ai/model/v5_momentumone_reset_training.lock

Previous checkpoints (including brwr_policy_v5_groupbalanced_reset.pt),
training histories, backups and game rules remain untouched. A copy of the
new checkpoint is made under ai/model/backups/ before each training run.
Subsequent calls to this NEW script resume its own checkpoint.

DIAGNOSTICS
V5M1_ACTIONS lists counts of raw legal candidates and VIRTUAL SLOTS, plus
observed Cast/Momentum choices on steps where both were available.
V5M1_REAL_PROBS independently recomputes the expected probabilities at
those real steps from the model used during the game. These figures should
NOT automatically be exactly 33/67: real games have differing scores and
additional available categories. They can reveal remaining policy bias.

VALIDATION STATUS
Python unit tests and syntax checks were executed while preparing this ZIP.
Godot/Python real-engine probability parity and a full simulated game must
be validated on your Windows project. The launcher aborts before running
any game if this parity check fails.
