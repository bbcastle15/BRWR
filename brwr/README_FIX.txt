BRWR Persistent Prefix Batch — Seed Fix v2
==========================================

Problem: Godot 4 JSON.parse_string may parse integer JSON numbers as floating
values. The batch builder converted manifest seed and bots with str(), giving
"20270491.0" and "4.0". The single-episode CLI parser rejects those strings.

INSTALL
-------
Copy build_persistent_prefix_batch.py into the BRWR/brwr root folder,
replacing the version from Persistent Prefix Batch v1.
No other files require changing. The benchmark automatically regenerates
ai/ai_policy_prefix_batch_match.gd from this updated generator.

TEST (from BRWR/brwr)
---------------------
powershell -ExecutionPolicy Bypass -File .\run_persistent_prefix_benchmark.ps1 -Games 1

If successful, test 3 games:
powershell -ExecutionPolicy Bypass -File .\run_persistent_prefix_benchmark.ps1 -Games 3

The fix normalizes BOTH seed and bots to decimal integer CLI strings and checks
that manifest values are integral before invoking the episode worker.

Only the generated AI runner is affected. game.gd, rules and model checkpoint
are untouched. Godot execution was not available in the packaging environment.
