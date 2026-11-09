BRWR — AI-only board refresh optimization test
==============================================

Why: profiling of seed 20270491 measured 595 calls to
refresh_all_player_boards(), totaling 9.499675 s. The function refreshes
EventBoard, previews and graphic player boards even when HUD is disabled.

This patch alters ONLY build_school_cache_variant.py to insert the following
into the generated ai/game_school_cached.gd function:

    func refresh_all_player_boards() -> void:
        if not enable_beta_hud:
            return
        ...original body...

The original game.gd is not changed. The original cached-game function
remains unchanged when enable_beta_hud is true. For this experiment, the
AI runner sets enable_beta_hud=false. The baseline worker is not changed.

Installation: extract apply_ai_board_refresh_guard.py into the BRWR/brwr
folder, where build_school_cache_variant.py already exists.

From PowerShell in BRWR/brwr:
    $python = "$env:USERPROFILE\ai-env\Scripts\python.exe"
    & $python .\apply_ai_board_refresh_guard.py

Then run one controlled comparison (baseline, cold cache, warm cache):
    powershell -ExecutionPolicy Bypass -File .\run_school_cache_benchmark.ps1 -Games 1

Do not accept the optimization unless SCHOOL_CACHE_PARITY_OK appears for
both comparisons and SCHOOL_CACHE_BENCHMARK_COMPLETE is printed. The parity
script compares schools, transition sequence, final scores and round,
not merely winner or decision count. Expected diagnostic:
    BRWR_AI_BOARD_REFRESH_GUARD_GENERATED disabled_when_enable_beta_hud_false=1

If parity is verified, rerun with -Games 3 for a better measurement:
    powershell -ExecutionPolicy Bypass -File .\run_school_cache_benchmark.ps1 -Games 3

Undo (restores original generator):
    & $python .\apply_ai_board_refresh_guard.py --undo

The next invocation of the existing benchmark regenerates the unmodified
AI variant. Previously generated AI-only files may remain, but are replaced.

Safety: Does not edit game.gd, spells, JSON, training history or model weights.
Godot execution and equivalence must still be validated on Windows.
