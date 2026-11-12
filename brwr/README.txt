BRWR v5 numeric selection parity fix

Extract fix_v5_numeric_selection.py into the project root BRWR\brwr.
Run from PowerShell:
  & "$env:USERPROFILE\ai-env\Scripts\python.exe" .\fix_v5_numeric_selection.py
  powershell -ExecutionPolicy Bypass -File .\run_v5_score_diagnostic.ps1

The target file is ai/ai_v5_semantic_encoder.gd only.
Original file backup is written to ai/runtime/ai_v5_semantic_encoder_before_numeric_fix.gd.txt.
Does NOT touch model files, the original v4 policy or train.py.

If V5_SCORE_DIAGNOSTIC_COMPLETE reports mismatch_cases=0, run:
  powershell -ExecutionPolicy Bypass -File .\start_optimized_v5_training.ps1 -PrepareOnly

Only if V5_PREPARE_COMPLETE passes should you start a single training episode.
