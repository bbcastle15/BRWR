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
- `avatar_rules.gd`: scenari isolati di effetti, reazioni ed Eventi (144 controlli).
- `avatar_flow.gd`: attivazioni, Dominion, Comandi aggiuntivi, cambio Luna,
  cleanup, Evocations e snapshot client con privacy (46 controlli).
  Entrambe le suite Avatar sono incluse anche nella verifica predefinita.
- `avatar_protections.gd`: Protections umane contro Comandi e reazioni Avatar,
  danni ad area, scarti e isolamento della protezione fra Comandi; inclusa
  nella verifica predefinita.
- `avatar_movement.gd`: destinazione grigia di Book of Nature, Speed 2 e
  attribuzione delle scelte alla Corona.
- `avatar_board_ui.gd`: vera board Avatar al posto della PlayerBoard, apertura
  e ripristino, Memories HD, Evocations e targeting dei cubi.
- `avatar_art_hd.gd`: verifica caricamento e risoluzione delle 47 carte.
- `avatar_menu.gd`: accesso al playtest, difficoltà e limiti dei posti.
- `avatar_playtest_fixes.gd`: 26 controlli su board verticale, danni delle
  Evocations, movimento visibile, griglia Upgrade, piani selezionabili dalla
  Corona, Command fisico delle Forgotten e massimo 5 umani più Avatar.
- `avatar_publication.gd`: 23 controlli su materiali vettoriali, tre retri,
  Destino/Infectio, ultimo danno leggibile, selezione token Avatar e conferma
  della Preparation dopo avere consultato le memorie.
- `avatar_layouts.gd`: controllo dedicato dei layout 2–6; eseguibile anche con
  renderer grafico per salvare le catture nella cartella evidence.
- `presentations.gd`: 156 controlli precedenti su Heka, privacy/presentazioni,
  animazioni e portrait delle Evocations.
- `playtest.gd`: regressioni Forge/Anubis e segnalazioni precedenti.
- `schools.gd`: integrazione scuole.
- `alternative_rooms.gd`, `alternative_rooms_ui.gd`: stanze alternative e UI.

I test UI headless verificano stato/visibilità dei controlli. Il collaudo visivo
reale e la prova online tra due PC rimangono necessari per la modalità Avatar.

Se le regole o il comportamento atteso cambiano, verificare la fonte prima di
adattare un test. Non disattivare controlli solo per ottenere un esito positivo.

Terzo playtest: `avatar_jinx_playtest.gd` aggiunge 24 controlli su Jinx visibili,
presentazione/ripresa effetti, FAQ Vulnerability, Corrupted Spear con/senza
Slowness e centratura Anubis. Suite completa 837 asserzioni. Artwork HD fedele
ancora incompleto: facce runtime ripristinate agli originali, vedi RIPRENDI_QUI.md.
