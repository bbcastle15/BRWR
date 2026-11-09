BRWR — Submit/Resolution Profiler: robust sidecar logging (fix v2)

Issue: All three games finish and parity passes, but summarize_submit_profile.py
finds no BRWR_SUBMIT_PROFILE_JSON marker in the stdout log. This patch writes
profile data directly to a small JSON sidecar file, then prints only its path.

Installation: extract build_submit_profile.py and summarize_submit_profile.py
into C:\Users\bigba\Desktop\BRWR\brwr, overwriting only these two files.

Then run:
  powershell -ExecutionPolicy Bypass -File .\run_submit_profile.ps1 -Games 3

Expected near each episode end:
  BRWR_SUBMIT_PROFILE_FILE C:/.../ai/datasets/submit_profile_episode_....jsonl.submit_profile.json

Expected summary:
  BRWR SUBMIT/RESOLUTION PROFILE ...
  SUBMIT_PROFILE_COMPLETE ...
  CHECKPOINT_UNCHANGED | SUBMIT_PROFILE_DONE

No changes to game.gd, Python trainer, AI weights, or game rules.
The previous 3 runs cannot be summarized retrospectively unless the old logs
contain the complete inline JSON marker; this patch will collect new profiles.
