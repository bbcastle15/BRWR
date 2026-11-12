BLACK ROSE WARS REBIRTH — V5 MOMENTUM-ONE SAFE RESUME + AUDIT
===============================================================
Goal: verify the rebuilt Arena auto-cast receipt fix at game 131, then
inspect actual learning before additional changes. DO NOT reset the model.

Includes the previous targeted Arena fix, plus read-only audit and safe runner.
No production game rules, momentum probabilities, terminal reward coefficients,
optimizer configuration or earlier checkpoint files are changed.

Extract ZIP CONTENTS into the project root:
 C:\Users\bigba\Desktop\BRWR\brwr

PowerShell from there:
  Expand-Archive -Path "$env:USERPROFILE\Downloads\BRWR_V5M1_SafeResume_Audit.zip" -DestinationPath "C:\Users\bigba\Desktop\BRWR\brwr" -Force

Before training, backup is created automatically. First:
  powershell -ExecutionPolicy Bypass -File .\v5m1_safe_resume.ps1 -Stage Preflight -ExpectedGames 130

Then test only game 131:
  powershell -ExecutionPolicy Bypass -File .\v5m1_safe_resume.ps1 -Stage Smoke -ExpectedGames 130

Expected success indicators:
  V5M1_RESUME_OK games=130
  V5M1_ROOMCAST_PROVENANCE_BUILD_OK generated_game_only=1
  MOMENTUM_ONE_PARITY ... mismatches=0
  V5M1_ROOMCAST_PROVENANCE game=131 confirmed=...
  V5M1_GAME_SAVED 131 ... updated=1 ... checkpoint_games=131
  V5M1_RUN_OK checkpoint_preserved_and_advanced=1

If and ONLY IF game 131 saved, run a small pilot:
  powershell -ExecutionPolicy Bypass -File .\v5m1_safe_resume.ps1 -Stage Pilot -ExpectedGames 131 -Games 20

Read-only audit at any time:
  powershell -ExecutionPolicy Bypass -File .\v5m1_safe_resume.ps1 -Stage Audit -RecentEpisodes 12
Output: .\v5m1_training_audit.txt
Logs:   .\ai\datasets\v5m1_run_logs\

The audit reports checkpoint/history consistency, per-25-game windows of
performance (NOT controlled benchmark), and checks spell-ID attribution in
recent saved episodes. The audit will NOT alter existing episodes/receipts.
For complete inspection use -RecentEpisodes 0, but it may read several GB.
Do not send a huge episode; send the audit txt and last 30 lines of the run log.

IMPORTANT LIMITS
- The current run begins from the existing 130-game checkpoint. If it has
  changed, the ExpectedGames safeguard stops rather than overwriting it.
- AI-only receipt patch still needs Godot verification on user's computer.
- If 131 fails, do not proceed to Pilot and do not bypass validation.
- No -KeepEpisodes on Smoke/Pilot: successful new episode files can be cleaned
  after the model is saved. Existing historical files are untouched.
- Training history has mixed scenarios. A rising average score in the audit
  does not by itself prove learning. A controlled held-out evaluation is still
  needed before selecting reward variants or doing another 5,000 games.
