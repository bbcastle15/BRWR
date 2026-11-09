BRWR — Resolution Deep Profiler (AI-only, v1)

Purpose:
  Pinpoint time inside _handle_resolution_completion and process_resolution_stack
  without changing the rules, UI guards, checkpoint, or original game.gd.
  Uses the existing cached AI scene, guarded UI, 50 earlier timing wrappers plus
  19 new synchronous phase, trigger, movement, and UI-cleanup wrappers.

Prerequisites (already installed by the user):
  - Working school cache benchmark + board_refresh_guard + targeted_ui_guards_v2.
  - Existing scripts: build_school_cache_variant.py, prepare_school_cache.py,
    check_school_cache_parity.py, export/check native policy, and Godot v4.7.2.

Copy these 3 files into C:\Users\bigba\Desktop\BRWR\brwr.
Then run in PowerShell from that folder:
  powershell -ExecutionPolicy Bypass -File .\run_resolution_deep_profile.ps1 -Games 1

If the summary fails but sidecar exists:
  powershell -ExecutionPolicy Bypass -File .\run_resolution_deep_profile.ps1 -SummaryOnly

This runner regenerates ONLY ai/ isolated versions, verifies UI guards,
Godot syntax and full same-seed decision/ending parity, and hashes the checkpoint.
Nothing touches game.gd, game.tscn, AI weights, original gameplay, or rules.

Important:
  Do not compare profiled-wall time to an unprofiled warm benchmark as a
  pure speedup; profiler instrumentation itself costs time. Compare function
  exclusive/inclusive time within same seed.
  No image or rule computations are skipped by this package.
