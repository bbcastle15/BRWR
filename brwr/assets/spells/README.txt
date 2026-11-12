BRWR AI v5 -- PHASE 1: candidate semantic features, audit and isolated warmstart
==============================================================================

This experiment fixes an actual flaw in v4: many candidate actions differed only
in their index, even when the bridge exposed spell IDs or target rooms. V5 keeps
all 128 old features and appends 256 semantic coordinates derived from the
OWNER-VISIBLE candidate descriptor. This phase does NOT train or replace v4.

INSTALL ALL FILES, keeping the ai/ subfolders, into BRWR/brwr:
  run_v5_encoder_audit.ps1
  ai/python/v5_encoder.py
  ai/python/v5_experiment.py
  ai/python/test_v5_encoder.py
  ai/python/v5_real_decision_samples.jsonl
  ai/ai_v5_semantic_encoder.gd
  ai/ai_v5_encoder_parity.gd

The existing ai/python/train.py, ai/ai_native_policy_v4.gd and checkpoint v4
are required and are NOT overwritten.

RUN IN POWERSHELL from BRWR/brwr:
  powershell -ExecutionPolicy Bypass -File .\run_v5_encoder_audit.ps1

Optional: audit an existing full episode instead of bundled older real examples:
  powershell -ExecutionPolicy Bypass -File .\run_v5_encoder_audit.ps1 -Episode .\ai\datasets\my_episode.jsonl

Only AFTER the GDScript feature parity test passes, optionally initialize v5:
  powershell -ExecutionPolicy Bypass -File .\run_v5_encoder_audit.ps1 -InitV5

This creates ai/model/brwr_policy_v5_init.pt, NEVER ai/model/brwr_policy_v4.pt.
The new checkpoint starts with equivalent outputs to v4; the 256 new weights
are initially zero; the optimizer must be fresh because the input shape changed.
The v5 counter is zero: the 500 previous games are v4 pretraining, NOT 500 v5
games. The v5 runner/trainer is NOT implemented in this phase. DO NOT use
start_optimized_training.ps1 for v5; that script is specifically for v4.

IMPORTANT LIMITATIONS:
- Some physically identical cards cannot be distinguished without meaningful
  identity fields. Process-specific Godot instance IDs are deliberately ignored.
- The 256-bucket hashing may collide. Audit reports unresolved collisions.
- The bundled real episode samples are OLD, not the 500-game checkpoint policy.
- Godot 4.7.2 parity has not been executed by the author; only Python-level
  checks and source generation have been tested.
- No new reward shaping in this patch. We will test the encoder improvement
  separately from changes to reward or advantage baseline.
