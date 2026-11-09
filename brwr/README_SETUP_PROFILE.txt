BRWR - Setup Profiling (Godot native policy)

PURPOSE
The previous deep profiler reported ~39 s of "Initial setup/loading" over 3
matches. This includes load(game.tscn), scene instantiation, the synchronous
root.add_child()/_ready(), TWENTY initial process_frame waits, model loading and
game.start_game_flow(); it is NOT just the file-loading cost. This patch times
each stage independently before proposing optimizations.

INSTALLATION
Extract build_native_setup_profiler.py and run_native_setup_profile.ps1
beside project.godot in C:\Users\bigba\Desktop\BRWR\brwr.
Requires already installed native inference + valid PyTorch/Godot parity.

RUN (PowerShell in BRWR\brwr)
  powershell -ExecutionPolicy Bypass -File .\run_native_setup_profile.ps1 -Games 3

Takes same three reference seeds / scenarios as the previous native benchmark:
  20270491 : 4 bots, none
  20270492 : 6 bots, none
  20270493 : 3 bots + Possessed Apprentice

For a faster single-match diagnostic:
  powershell -ExecutionPolicy Bypass -File .\run_native_setup_profile.ps1 -Games 1

WHAT CHANGES
- Re-exports saved policy weights, checks PyTorch/GDScript parity, and
  regenerates current native worker as in prior benchmark.
- Generates ai/ai_policy_native_setup_profile.gd (separate worker).
- Records to ai/datasets/native_setup_episode_*.jsonl (separate output).
- Saves detailed logs and summary.json in ai/native_setup_profile_logs/<time>.
- Does NOT modify game.gd, ai_bridge.gd, train.py, RL weights, or policy source.
- Verifies the checkpoint SHA256 before and after.

METRIC DEFINITIONS
- 'Legacy setup': exactly the interval previously classified as setup, from
  just before loading game.tscn to the return of game.start_game_flow().
- 'root.add_child(game)': includes synchronous scene-tree notifications and
  _ready() code. It is NOT only the cost of inserting an object in a list.
- 'initial 20 process_frame waits': includes engine work between frames.
  It is not solely idle sleep time.
- 'start_game_flow': synchronous return of that method; async/deferred work
  after it returns is attributed to later game execution, not this category.
- Stage times are observational and include a tiny profiling overhead.
- 'process wall' contains Godot launch/import/shutdown overhead, unlike
  the internal setup timing. Process wall is not equal to game CPU time.

IF IT FAILS
Do not change game.gd. Send full console error and last 40 lines from the
per-game .log file. The builder stops if source anchors do not match.
