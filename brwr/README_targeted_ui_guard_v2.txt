BRWR — AI-only direct board refresh optimization V2
===================================================

Measured on 3 guarded-profile games (1262 decisions):
  refresh_player_board()        465 calls, 4.182 s exclusive
  _refresh_damage_boards()       50 calls, 0.546 s exclusive
  refresh_all_player_boards()  1665 calls, 0.013 s (V1 guard already works)

V2 guards the first two render-only functions, but ONLY in generated
ai/game_school_cached.gd. Original game.gd and rules are not modified.

PREREQUISITES
- Existing school-cache benchmark installed.
- V1 board refresh guard already installed in build_school_cache_variant.py.
- Run from BRWR/brwr folder.

INSTALL
1. Extract apply_ai_targeted_ui_guards_v2.py into BRWR/brwr
2. Run in PowerShell:
   $python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
   & $python .\apply_ai_targeted_ui_guards_v2.py

CONTROLLED PARITY TEST (first seed, baseline vs optimized):
   powershell -ExecutionPolicy Bypass -File .\run_school_cache_benchmark.ps1 -Games 1

Accept only if ALL appear:
  BRWR_AI_TARGETED_UI_GUARDS_GENERATED refresh_player_board=1 damage_boards=1
  SCHOOL_CACHE_PARITY_OK (twice)
  SCHOOL_CACHE_BENCHMARK_COMPLETE | parity passed | checkpoint unchanged

If successful, benchmark all three seeds:
   powershell -ExecutionPolicy Bypass -File .\run_school_cache_benchmark.ps1 -Games 3

IMPORTANT: The current benchmark's parity check covers the first seed only;
other seeds are timing measurements, not full parity tests.

ROLLBACK to V1 only (V1 remains in place):
   & $python .\apply_ai_targeted_ui_guards_v2.py --undo
Then rerun the benchmark to regenerate AI-only files.

DIRECT SAVINGS SUGGESTED BY PROFILE: 4.728 s across 3 games or 1.576 s/game.
Actual speedup may differ. Previous three-game benchmark: 16.20 s/game.

No Godot executable is available in this environment, so run the Windows
validation before using the change in training.
