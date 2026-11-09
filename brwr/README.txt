BRWR — Persistent Parity: Legal Hand-Token Identity Fix v6
=========================================================

WHAT HAPPENED
- Seed 20270491: semantic parity passed (452 decisions).
- Seed 20270492: semantic parity passed (568 decisions).
- Seed 20270493: first detected remaining difference at record 221 in
  $.legal_candidates[0].detail.token, comparing two 'hand:<signed-int64>'
  values. These look like transient, process-specific object IDs.

WHAT CHANGES
The checker now compares hand:<ID> strings in a STRICT, narrow set
of legal candidate fields: detail.token, payload.selection, payload.ai_select,
payload.token and synthesized labels (hand:<ID>, Select hand:<ID>).
The prefix must match and the numeric ID must obey the SAME persistent
one-to-one mapping for that episode used by Quest/Evocation instance IDs.
This is not a blanket ignore: if one ID changes mapping, is recycled
inconsistently, is out of int64 range, or collides with another ID, the
check fails. Candidate order, remaining metadata, selected IDs, gameplay
state, round, rewards, scores and terminal results remain strict.
It also retains the narrowly scoped exception for animation-only attack
feedback pixel x/y coordinates from v5.

INSTALL
Extract check_persistent_episode_parity.py and diagnose_persistent_batch.py
into BRWR\\brwr. Overwrite the previous v5 checker/diagnostic.
Do NOT replace the persistent worker, game.gd, or model.

NO SIMULATIONS NEEDED YET
  & "$env:USERPROFILE\\ai-env\\Scripts\\python.exe" .\\diagnose_persistent_batch.py 20270491 20270492 20270493

If all three print PERSISTENT_SEMANTIC_PARITY_OK and failures=0, previous
JSONL evidence verifies semantic parity for these three seeds under this
explicit allowlist. Do NOT claim byte identity: volatile IDs/attack coords
differ between runs. A runtime benchmark may then be repeated independently
for a stable speed estimate.

If ANY other difference appears, stop. Share the exact path and values.
Do not use persistent worker for training until 3-game parity passes.

Python standard library only. No Godot restart needed for diagnosis.
