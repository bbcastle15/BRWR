BRWR — Deep _ready() profiler (isolated, no gameplay changes)

INSTALL
  Unzip both root-level files in C:\Users\bigba\Desktop\BRWR\brwr:
    build_ready_deep_profile.py
    run_ready_deep_profile.ps1

RUN
  powershell -ExecutionPolicy Bypass -File .\run_ready_deep_profile.ps1 -Games 3

Reuses the original seeds and configurations:
  20270491 / 4 bots / no Avatar
  20270492 / 6 bots / no Avatar
  20270493 / 3 bots + Possessed Apprentice

SAFETY
  No original game.gd, game.tscn, ai_bridge.gd, trainer, policy or checkpoint edits.
  The builder reads CURRENT game.gd, game.tscn and the generated native worker.
  It builds only:
    ai/game_ready_deep_profile.gd
    ai/game_ready_deep_profile.tscn
    ai/ai_policy_native_ready_deep_profile.gd
  Episode datasets are separated with a native_ready_deep_episode_ prefix.
  The checkpoint SHA256 is checked before and after. No weight updates occur.
  Build stops if expected anchors are not present (instead of guessing).

REPORT
  root.add_child total; time before game._ready; main game._ready before
  the first await; top 18 stages of game._ready, ordered by time.
  Details in ai/ready_deep_profile_logs/<timestamp>/summary.json.

INTERPRETATION
  root.add_child includes child-node _ready notifications AND game._ready.
  The part 'before game._ready' is NOT necessarily pure CPU: it includes
  child initialization, tree notifications and any synchronous engine work.
  Some game._ready() stages run after an await and can fall OUTSIDE the time
  measured by root.add_child(); do not sum these indiscriminately.
  Timings are wall-clock, measured by Time.get_ticks_usec().

VERIFICATION
  Correctness still needs validation on Godot 4.7.2 Windows.
  If a build/parsing error occurs, send the console output and the last 40
  lines from the corresponding log. This is an instrumented *copy* of game.gd,
  not a gameplay patch.
