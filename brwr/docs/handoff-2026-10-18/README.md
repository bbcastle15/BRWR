# Controlli conservati per la nuova chat

Gli script erano in cartelle temporanee del PC originale. Sono stati conservati
qui appositamente per il passaggio al laptop, con i percorsi delle catture
resi portabili. Non sono codice incluso nel gioco: `docs/` è esclusa dall'export.

Dalla cartella `brwr`, in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\handoff-2026-10-18\Verify-Resume.ps1 -Godot 'C:\percorso\Godot_v4.7.2-stable_win64_console.exe'
```

Aggiungere `-Suite all` per eseguire anche le regressioni delle scuole,
del playtest precedente e delle stanze alternative. Il verificatore importa
il progetto, verifica JSON e asset, esegue Godot headless e scrive i log in
una nuova cartella temporanea. Non installa programmi e non modifica le regole.

- `avatar_smoke.gd`: 41 asserzioni e passaggio sui 30 Comandi in sequenza;
  NON copre tutti gli esiti né tutte le reazioni/eventi. Va esteso prima del rilascio.
- `presentations.gd`: 156 controlli precedenti su Heka, privacy/presentazioni,
  animazioni e portrait delle Evocations.
- `playtest.gd`: regressioni Forge/Anubis e segnalazioni precedenti.
- `schools.gd`: integrazione scuole.
- `alternative_rooms.gd`, `alternative_rooms_ui.gd`: stanze alternative e UI.

I test UI headless verificano stato/visibilità dei controlli. Il collaudo visivo
reale e la prova online tra due PC rimangono necessari per la modalità Avatar.

Se le regole o il comportamento atteso cambiano, verificare la fonte prima di
adattare un test. Non disattivare controlli solo per ottenere un esito positivo.
