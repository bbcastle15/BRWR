# Aggiornamento 22 ottobre 2026

Leggere `docs/PLAYTEST-2026-10-22.md`: correzioni ultimo playtest, test, asset scuola integrati e stato ancora incompleto della copertura maghi Codex Arcanum.

# Ripresa sul laptop — 18 ottobre 2026

Questo è il progetto corrente, comprese le modifiche non committate. L'utente
sincronizzerà l'intera cartella del repository con il laptop Windows. Questi
documenti conservano il contesto della chat, che sul laptop non sarà disponibile.
Non è una release di Possessed completata.

## Checkpoint corrente — 21 ottobre 2026

- Sostituzioni stanze limitate a `replaces`, mai per colore. Gaea: Emerald Rose, Thorny Clearing, Life Fountain, Indoor Forest non selezionabili finché lo scenario non è implementato. Guardia condivisa fra menu, setup casuale e rete. Test `room_families.gd`: 3306 verifiche; `alternative_rooms.gd`: 122, zero errori.
- Regolamenti mancanti raccolti in `../materials/official_missing`; inventario e abbinamenti in `docs/ROOMS-AND-RULEBOOKS-2026-10-21.md`.
- Artwork runtime aggiornato: `approved/` contiene tutti i 46 PNG restaurati (30 Comandi, 15 Eventi, Possessed), ha precedenza sull'atlante. Il resoconto del terzo playtest qui sotto è storico e superato. Vedi `docs/AVATAR-HD-ARTWORK.md`. Nessun export aggiornato.
- Cemetarial Mist Light: movimento di un modello entro distanza 1 dalla stanza bersaglio, danno nella stanza originaria; ripresa Explore dopo trappola con contesto vuoto corretta. Box descrizione effetto separato dagli input. Test dedicato: 17 verifiche superate.

## Checkpoint precedente — storico

### Terzo playtest del 19 ottobre — Jinx, Anubis e rifiuto del redesign

- **Artwork HD NON completato.** L'utente ha rifiutato le facce ricomposte
  in `production/`: vuole gli stessi originali, solo più nitidi. Anche i nuovi
  tentativi ImageGen hanno alterato pittogrammi. `AvatarArt` usa quindi di
  nuovo i 46 ritagli originali di `atlas.json` (30 Comandi, 15 Eventi, Possessed),
  senza il bordo aggiunto e senza reinterpretazioni. Risoluzione originale,
  non dichiarare queste carte HD o pronte per pubblicazione. I tre retri e
  il materiale della board restano quelli precedenti. I tentativi in
  `faithful/` sono RIFIUTATI e ignorati da Godot, non asset approvati.
- Avatar Board: facce di tutte le Jinx in griglia scorrevole, clic per
  ingrandire, cubi di avanzamento neri e indicazione della velocità effettiva.
- Nuove assegnazioni Jinx presentate a schermo con la stessa pausa/click
  di Eventi e Spell. Si usa un frame `jinx_assignment` nello stack esistente;
  solo presentazione, nessuno stato delle regole duplicato. L'Avatar delega
  alla Corona la conferma, anche nelle proiezioni online.
- Anubis: centri dei due token azione mappati sui recessi della sua immagine
  reale; gli altri Maghi conservano la posizione precedente.
- Vulnerability: FAQ ufficiale v1.2, p.6, dice esplicitamente **NO** al danno
  sulla propria assegnazione. Già implementato correttamente, regola invariata.
- Corrupted Spear: non riprodotto un arresto errato. Test con due stanze blu
  equidistanti e scelta Corona: percorre 2 stanze; con Slowness percorre 1.
  L'utente non ricorda la stanza e conferma che Slowness potrebbe esserci stata.
- Suite aggiunta `avatar_jinx_playtest.gd`: 24 asserzioni su Anubis,
  assegnazione/presentazione, ripresa dello stack, Vulnerability, Jinx visibili
  e movimento con/senza Slowness. Catture `anubis-actions-centred.png`,
  `avatar-visible-jinxes.png`, `jinx-assigned-presentation.png` in evidence.
  Nessun export o commit. Le note seguenti sono storiche e non certificano HD.

### Secondo playtest del 19 ottobre — materiali e Preparation

- La plancia usa `production/board.svg`, una ricostruzione vettoriale pulita:
  lo screenshot `board_reference.png` è solo una fonte storica. Numeri del
  tracciato disegnati da Godot (l'importatore SVG non supporta il testo SVG).
  Limite vita = contorno vuoto, nessun cubo bianco sopra all'ultimo danno.
- 30 Comandi Possessed e 15 Eventi ricomposti a 1536×2304 tramite
  `tools/build_avatar_production.py`: glifi originali BRWR estratti dal PDF
  del regolamento, non inventati dal generatore. Simboli delle stanze p.25:
  verde foglia, grigio teschio, viola ovale, giallo gemma, blu occhio,
  rosso spade. Tipografia originale dove disponibile, con fallback per i
  caratteri senza contorno nei subset del PDF. Stato/regole sempre dai JSON.
- Tre retri per Luna restaurati con ImageGen dagli allegati utente, in
  `restored/command_back_1.png` … `_3.png`. Il mazzo coperto mostra il retro
  della Luna corrente. Nessuna faccia nascosta esposta dal nuovo renderer.
- Destino e Infectio sulla carta/scheda Avatar, con colore del proprietario,
  aggiornati dallo stato MageState. Nessuno stato duplicato nella UI.
- Le Evocations Avatar e i loro cubi sono selezionabili dal token sul Lodge,
  come quelle umane; l'ispezione della board non si apre per selezionarle.
- Raging Lash (`assets/spells/raging_lash.png`): sola correzione grafica del
  simbolo dopo «convert 1» nel lato Dark, ora Damage. Effetti JSON intatti.
- Blocco Preparation riprodotto: `open_public_memories()` riutilizzava
  HandOverlay e cancellava la modalità/richiesta attiva di Preparation.
  Ora usa ReferenceCardPreview separato, conserva draft e conferma. Test
  completo: prepara Raging Lash/Empathy, consulta memorie proprie e Avatar,
  chiude, riapre e conferma entrambe le spell con i lati selezionati.
- Nuova suite `avatar_publication.gd`: 23 asserzioni, inclusa prova grafica.
  Prompt e provenienza raster in `production/raster_provenance.json`.
  I font intermedi sono esclusi dall'importazione con `source_fonts/.gdignore`.
- Regresso completo: **813 asserzioni** passate, più controlli menu/47 texture
  e 13 JSON. Ultimo import e test grafico dopo i materiali finali: 23/23,
  nessun errore. Cattura `evidence/avatar-production-board.png`; log finali
  `avatar-materials-complete-*`. Materiale legno/pergamena in `production/`,
  prompt in `material_provenance.json`. Nessun export nuovo o commit.
  Ultima cattura verificata dopo correzione dei livelli del materiale:
  `avatar-materials-complete-visual-v2.log`, 23/23, senza errori.

### Correzioni dal playtest del 19 ottobre — precedenza sulle note HD sotto

- Massimo **5 umani + Avatar** (6 posti totali), applicato al setup locale,
  all'hosting e all'avvio online. Senza Avatar restano 6 umani.
- Board ingrandita verticale, con carta Possessed e contatori leggibili;
  stessa board del tavolo, nessuna PlayerBoard Avatar separata.
- Il vecchio rettangolo giallo era il limite di Health: ora cubo grigio,
  spiegato nel titolo insieme a HP attuali/massimi. Danni colorati sulle
  Evocations della board; targeting conserva rotazione e scala delle carte.
- Movimento Evocations: chiude la board, mantiene visibile il tragitto con
  la camera e conserva animazione/pausa di risoluzione. Le animazioni delle
  PlayerBoard attendono la fine della risoluzione delle Evocations.
- Upgrade in griglia con proporzioni orizzontali reali e scorrimento verticale;
  ispezione grande supportata anche per gli Upgrade.
- Command tramite token fisico evidenzia anche le Forgotten sul tavolo.
  Minotaurus in fase Evocation apre subito la scelta reale dell'ordine,
  senza la selezione artificiale della stanza iniziale.
- Blocco UI: i piani delle Evocations per la Corona perdevano i percorsi
  durante la conversione in opzioni pubbliche. Ora li conservano; i piani
  senza movimento passano direttamente alla scelta finale e i percorsi
  non visualizzabili hanno pulsanti di ripiego. Le scelte Avatar aprono
  la board corretta anche se era già aperta quella di un umano.
- Il redesign HD precedente è stato rifiutato dall'utente. `AvatarArt`
  preferisce ora `assets/avatars/possessed/restored/` per i 15 Eventi e
  Possessed. Restauro ImageGen dagli screenshot, fonti intatte; prompt e
  provenienza in `restored/provenance.json`. La fedeltà grafica/simbolica
  NON è certificata dal test di risoluzione delle immagini.
- Test dedicato: `checks/avatar_playtest_fixes.gd`, 26 asserzioni superate
  anche con renderer grafico. Catture `evidence/avatar-portrait-fixed.png`
  e `evidence/upgrade-grid-fixed.png`; log `avatar-playtest-visual-final.txt`.
  Il salvataggio della specifica partita bloccata dell'utente non era presente:
  verificato il percorso equivalente di scelta della Corona.
- Regressione completa `Verify-Resume.ps1 -Suite all` conclusa: **790
  asserzioni**, controllo menu e caricamento 47 immagini superati; 13 JSON
  validi. Reimportazione finale dei restauri riuscita. Nessun export nuovo.

### Avatar Board e carte HD — ultimo blocco del 19 ottobre

- Ricostruite 47 carte in `assets/avatars/possessed/hd/`: 30 Comandi,
  15 Eventi, carta Possessed e retro. Frame/illustrazione nuovi con ImageGen;
  testo composto separatamente a 1024×1536 (Possessed 1536×1024).
  Generatore ripetibile: `tools/build_avatar_cards.py`; prompt e fonti in
  `docs/AVATAR-HD-ARTWORK.md`. Gli screenshot originali sono conservati.
- Nessuna PlayerBoard istanziata per Avatar: `player_boards[avatar_index]`
  punta alla vera `AvatarBoard` per compatibilità con refresh e scelte cubi.
  Il TabletopShell sposta la STESSA board nel modal e la ripristina alla chiusura.
  Clic sulla board sul tavolo o sul banner Possessed per aprirla ingrandita.
- Carta Avatar, mazzo/reazione pubblica, Memories/scarti sfogliabili, tre slot
  Evocations, danni, Quest risolte coperte, assegnazioni e Jinx sulla board.
  Clic sulle carte/mazzi per consultarle; le identità dei Comandi non rivelati
  restano nascoste. Ispezione Avatar/Comandi ingrandita rispetto al vecchio viewer.
- **Book of Nature** era erroneamente configurata verso verde: lo screenshot
  Moon 1 indica **grigio**. Corretto JSON e nuova carta. Test con sola stanza
  grigia a distanza 2 conferma due passi con Speed 2; una volta raggiunta la
  destinazione il movimento termina. Non è stato necessario cambiare Speed.
- Regolamento pp.37/40: board dedicata e Choice of Crown confermate. Scelte
  di destinazione/percorso in parità solo alla Corona; nessuna scelta quando
  esiste un'unica opzione. Test esplicito del prompt e del proprietario input.
- Godot 4.7.2 reale: regressione completa passata; nuove suite movimento
  (8), board UI finale incluso targeting cubi (10), verifica texture HD (47 carte) e menu; test grafico layout
  2–6 posti (25 controlli) passato. Catture e log in `docs/handoff-2026-10-18/evidence/`.
  Controllati visivamente board, scarti e layout nel renderer Compatibility.
- Playtest Avatar accessibile dal menu come prima. Nessun commit o export Web;
  prova online reale su due PC non eseguita in questo blocco.

Accesso al playtest (19 ottobre, aggiornamento più recente): il menu Avatar
è ora accessibile e offre Possessed come **playtest sperimentale**, con scelta
Apprendista/Maestro. `implemented` resta false e la selezione casuale non
include contenuti sperimentali. Scegliere Possessed, confermare, impostare il
numero di giocatori umani e premere "Modalità solo-test". Consente 1–5 umani
più Avatar; disattivandolo ripristina 2–6. Il precedente testo "menu disabilitato"
descrive i checkpoint storici, non lo stato attuale. Import Godot riuscito;
`checks/avatar_menu.gd` verifica selezione, difficoltà, limiti e disattivazione.
La build Web preesistente non contiene questo accesso: usare il progetto Godot.

Implementazione successiva del 19 ottobre: corrette due incompatibilità delle
Protections umane in `avatar_effects.gd`. Gli annunci Avatar includono ora
anche `event.data.targets/spell_context`, richiesti da Bone Shield; le
reazioni Avatar annunciano gli effetti ostili alla normale finestra dei trigger,
permettendo Caput Draconis Dark contro contrattacchi e conversioni. Gli effetti
che proteggono solo l'Avatar non annunciano falsi bersagli umani.
Nuova suite `avatar_protections.gd`: 29 controlli superati, integrata nel
verificatore predefinito. Copre anche area, scarti, bersagli non protetti e
assenza di protezione residua sul Comando successivo.
Regressione completa dopo queste correzioni: **746 controlli, zero fallimenti**,
import editor e 13 JSON validi. Evidenze aggiornate in
`docs/handoff-2026-10-18/evidence/2026-10-19-protections/`.

Aggiornamento 19 ottobre 2026: ripresi i test con Godot 4.7.2 reale.
`avatar_rules.gd`: 144 controlli superati; `avatar_flow.gd`: 46 controlli
superati, inclusi Dominion, budget 3/4 Comandi, cambio Luna, cleanup,
Evocations e snapshot host/client senza identità dei Comandi nascosti.
Corretto nel test flow il nome riservato `Projection` e isolato dal cambio
Luna lo scenario del Comando aggiuntivo (Potere iniziale dei Maghi a zero).
Le due suite sono ora incluse nel verificatore portabile predefinito.
Log in `docs/handoff-2026-10-18/evidence/avatar_rules.txt` e `avatar_flow.txt`.
Questi controlli non sostituiscono playtest visivo e online su due PC.
Menu Avatar ancora disabilitato; nessun commit o export automatico.
Verifica completa `Verify-Resume.ps1 -Suite all` terminata: 717 controlli,
zero fallimenti (41 smoke, 144 regole Avatar, 46 flow, 156 presentazioni,
115 playtest, 56 scuole, 134 stanze alternative, 25 UI stanze).
Import editor riuscito e 13 JSON validi; log completi in
`docs/handoff-2026-10-18/evidence/2026-10-19/`.
Prossimo blocco: plancia e presentazioni con verifica visiva, ulteriori casi
limite delle Protections e infine partita online reale.

Il setup per il laptop è pronto. L'utente ha autorizzato di proseguire qui e
chiede di aggiornare questo file dopo ogni blocco verificato. Priorità corrente:
test isolati degli effetti e delle reazioni di Possessed, poi ciclo partita,
plancia e sincronizzazione online. Il solo smoke test dei 30 Comandi non è
sufficiente: le carte vanno controllate con bersagli e stato ripristinati.
Menu Avatar ancora disabilitato. Ultima verifica completata: 197 controlli
(Avatar smoke 41 + presentazioni 156), import Godot e 13 JSON validi.

## Obiettivo da proseguire

Completare la modalità Avatar con Possessed, i suoi 30 Comandi e i 15 Eventi
forniti dall'utente. Solo dopo aver verificato tutte le meccaniche e la UI,
rendere disponibile la selezione Avatar manuale/casuale nel menu principale,
con difficoltà Apprendista (3 Comandi) o Maestro (4).

Leggere prima [il passaggio di consegne dettagliato](docs/HANDOFF-AVATAR-2026-10-18.md)
e `AGENTS.md`. Esaminare `git status` e `git diff`: molte modifiche precedenti
all'Avatar appartengono all'utente o a funzionalità già verificate e vanno preservate.

## Percorsi portabili

- Progetto: questa cartella, contenente `project.godot`.
- Regolamento, Codex e FAQ: `../materials/`.
- Screenshot Avatar dell'utente, già salvati: `assets/avatars/possessed/`.
- Motore richiesto: Godot 4.7.2 stable; individuare il percorso sul laptop.
- Test e verifica portabile: `docs/handoff-2026-10-18/` (esclusi dall'export).
- Risultati delle verifiche: `docs/handoff-2026-10-18/evidence/`.

Non dipendere dai vecchi percorsi `C:/Users/bigba/...` o dai file temporanei
della chat: immagini e controlli necessari sono stati salvati nel repository.

Se la sincronizzazione avviene tramite GitHub, includere anche i NUOVI file
non ancora tracciati: non basta trasferire il vecchio commit. Non sono stati
creati commit o eseguiti push automaticamente.

## Messaggio da incollare nella nuova chat Codex

> Riprendi lo sviluppo di BRWR da questo progetto. Leggi AGENTS.md,
> RIPRENDI_QUI.md e docs/HANDOFF-AVATAR-2026-10-18.md; controlla lo stato Git
> senza annullare modifiche esistenti. L'obiettivo è completare Possessed e
> la modalità Avatar secondo regolamento, FAQ e immagini già incluse.
> Le meccaniche sono in lavorazione: non considerarle complete solo perché
> esistono i JSON o passa il controllo di avvio. Esegui i controlli disponibili,
> completa gli effetti, verifica layout e sincronizzazione online, poi abilita
> la scelta manuale/casuale dal menu. Continua autonomamente, senza creare commit.
