# Passaggio di consegne: Possessed / modalità Avatar

## Stato effettivo

L'utente ha chiesto di preparare il trasferimento sul laptop prima di esaurire
il limite della sessione; ha poi precisato che sincronizzerà l'intera cartella
GitHub e serve soprattutto conservare il contesto di questa chat. Non occorre
un pacchetto di trasferimento separato. L'implementazione Avatar NON è una funzionalità
completata o validata integralmente. Il setup per il trasferimento è pronto;
l'utente ha poi autorizzato di continuare l'implementazione, aggiornando
periodicamente `RIPRENDI_QUI.md`. Consultare quel checkpoint per gli ultimi test.
`data/avatars.json` mantiene `implemented: false`: il pulsante Avatar del menu
è disabilitato finché `AvatarRules.available()` non restituisce contenuti pronti.
I test possono impostare esplicitamente `game.avatar_selection` per esercitare
Possessed senza abilitarlo agli utenti.

Non fare commit automatici. Non ripristinare file dal vecchio HEAD: si perderebbero
molti miglioramenti già richiesti e le nuove modifiche Avatar.

## Richiesta dell'utente

Completare Possessed utilizzando la sua carta, 30 Command Cards, 15 Avatar Event
Cards (5 per Luna) e plancia. Gli screenshot sono ora conservati nel progetto.
Al termine, selezione Avatar nel menu in analogia alla selezione delle stanze:
disattivato, casuale, selezione manuale. Per ora solo Possessed; sistema
estensibile agli altri Avatar. Non inventare effetti o modificare i layout
standard delle stanze per adattarli arbitrariamente.

## Fonti da usare

- `../../materials/BRWR_CORE_rulebook_ENG_v1.2.pdf`, pp. 34–40, in particolare
  pp. 36–40: setup, Comandi, reazioni, priorità, Evocations, cleanup.
- `../../materials/BRWR_FAQ&errata_2026-01-28_Refers to v1.0_ENG.pdf` (l'intestazione
  interna riporta febbraio 2026): reazioni oltre il limite, sconfitte fra effetti,
  Evocations assegnate, Starve, considerazione come Spell/Physical Action.
- `../../materials/Codex Arcanum.pdf`, p. 113: **Dark Blade usa priorità 1**,
  non 3 come stampato sulla carta. Questa correzione è già nel JSON.
- `assets/avatars/possessed/commands_1.png`, `_2.png`, `_3.png`: 10 Comandi/Luna.
- `events_1.png`, `_2.png`, `_3.png`: 5 Eventi/Luna.
- `sheet.png`: Possessed, 12 Health / 2 Strength / 2 Speed, Dominion.
- `board_reference.png`: immagine originale della plancia, orientata lateralmente.
- `atlas.json`: ritagli dichiarativi; le immagini originali non sono state alterate.
- Le immagini necessarie sono in `assets/avatars/possessed/`; non serve
  recuperarle dagli allegati temporanei della vecchia chat. I PDF e gli
  screenshot rimangono le fonti autorevoli.

## Architettura aggiunta

- `AvatarState` contiene SOLO mazzi per Luna, Comando attivo, limite/contatore,
  definizione e difficoltà. Il giocatore Avatar è l'ultimo `PlayerState`.
- `PlayerState.avatar` collega lo stato. MageState mantiene posizione/danni,
  PlayerState mantiene evocazioni/Quest. Potere e trofei rinviano allo stato
  della Rosa Nera; i cubi disponibili rinviano al pool BR dell'EventBoard.
- Hand e Grimoire Avatar rinviano allo STESSO mazzo della Luna corrente.
  I Comandi rivelati vanno nelle Memories; cleanup rimescola solo quelli
  rivelati sotto il mazzo della Luna di appartenenza.
- `AvatarRules` configura Possessed, Comandi nel database Spell esistente ed
  Eventi Avatar nel database Event esistente. Fornisce priorità, scelte della
  Corona, reazioni attraverso la normale trigger window e attivazioni Evocation.
- `AvatarEffects` e `AvatarEvents` sono frame sullo stack di risoluzione di Game:
  usano danni, movimento, sconfitta, evocazione e scelta già esistenti.
- `AvatarArt` usa AtlasTexture per i materiali forniti. `AvatarBoard` è una
  proiezione visiva dello stato; sostituisce la Cell dell'ultimo posto.
- MainMenu contiene la UI di scelta, ma è ancora disabilitata dal catalogo.
  La configurazione Avatar viene inviata ai client nel messaggio `begin`.
- NetworkProjection aggiunge conteggi e simbolo di reazione del retro, senza
  trasmettere identità o ordine dei Comandi nascosti. Da collaudare approfonditamente.

## Regole già considerate

- Avatar conta come un partecipante nella Loggia: 1–5 umani più Avatar, massimo
  6 posti. Solo locale consente 1 umano; lobby online resta almeno 2 umani.
- Non può ricevere la Corona; i pareggi reali sono scelte del suo possessore.
- Condivide Potere e pool di 30 cubi BR, ma Starve resta un pool separato.
- Non subisce danni BR; ignora Eventi rivolti ai Maghi. Umbra assegnata ad Avatar
  non danneggia nemmeno l'Evocation nello stesso slot (FAQ).
- 3 Comandi/Action Phase Apprendista, 4 Maestro; reazioni contano, Comandi
  aggiuntivi no. Non attivare Trap/Protection dopo il limite (FAQ).
- Cambio Luna immediato; conserva i mazzi separati.
- Dominion a INIZIO attivazione in Cell: piazza in Black Rose Room e non pesca.
- In Cell ignora sezioni Spell; le reazioni già in risoluzione continuano.
  Physical Actions in Cell solo se consentono Move/place (FAQ).
- Quest solo tramite effetti: guadagna il Potere stampato, ignora effetti della
  Quest; conta le Quest risolte nel punteggio finale.
- Conversione da destra; priorità 3 esclude Avatar e sue Evocations dai conteggi.
- Danni multipli: prima Maghi con più danni BR, poi più danni; Evocations dopo
  Maghi; parità alla Corona. Implementazione recente da verificare con risorse scarse.
- Evocations attivate I, II, III. Bersagli AI Mage prima di Evocation se
  attaccabili, poi distanza, danni, Potere. Mantiene la pipeline esistente.
- Throne ha internamente colore purple ma NON deve contare come una normale
  stanza viola per i Comandi/Eventi di colore; aggiunta esclusione.

## Contenuti JSON

`data/avatar_commands.json`: 30 voci uniche, 10/Luna. Moon 1 da Release Energy
a Tomb Reinforcements; Moon 2 da Release Force a Infernal Reinforcements;
Moon 3 da Tap into the Black Rose a Abyssal Reinforcements.
`data/avatar_events.json`: 15 voci compatibili con EventCardState.
`data/avatars.json`: una definizione Possessed, con priorità e gating.

## Cosa manca prima di abilitare Possessed

1. Testare OGNI effetto e reazione con stato controllato e risultati attesi.
   Il check Avatar incluso ha 41 asserzioni ed esercita i 30 Comandi in sequenza,
   ma NON prova ogni effetto: dopo sconfitte alcuni bersagli non sono disponibili.
   Non confondere smoke test con certificazione delle regole.
2. Verificare tutti i 15 Eventi: slot, Luna, Corona, award Power, tempi di trigger,
   passivi e scelte private. Verificare che `room_effect_resolved` esponga
   `room_color` e `source_room_id` come consumati da AvatarEvents.
3. Verificare pipeline completa setup → scelta Maghi umani → Study/Preparation
   → round robin Action → Evocations → cleanup/ricostruzione → fine partita.
   Testare turni senza azioni umane, Dominion, limite reazioni, additional Command,
   cambio Luna mentre il Comando è in corso, recycle/assenza duplicati nei mazzi.
4. Testare Protections umane contro sezioni Avatar: è stato appena aggiunto
   `announce_effect` con metadati del contesto per Caput Draconis/ignore Spell.
   Verificare cancellazione/bersagli persistenti e ordine di risoluzione.
5. Testare priorità e scelte Crown per area con cubi scarsi; attivazioni
   Cadaver/Colossus e tutti i piani AI. `prepare_evocation` passa le Evocations
   con abilità estese alla pipeline esistente: verificare i casi necessari.
6. Controllare interazioni con effetti generici su Hand/Grimoire/Memories,
   conversioni cubi, source owner -1 vs seat Avatar, Jinx, Starve, Trophies,
   defeat e scoring (evitare doppio conteggio Avatar e BR).
7. Verifica visiva plancia Avatar per 2–6 posti: orientamento/incastro/camera,
   salute, Comandi/Memories, Evocations, Quest risolte, token Avatar in Cell.
   La grafica è una prima implementazione NON validata visivamente. Le Evocations
   e le scelte dei cubi usano ancora la PlayerBoard esistente; completare
   presentazione coerente con la plancia Avatar senza duplicare stato.
8. Comandi a tutto schermo prima degli effetti: richiedono click Crown online.
   Per ora nessuna evidenziazione della singola sezione Spell/Physical/reaction.
   La carta non ha lati Light/Dark. Verificare leggibilità e gestione click.
9. Testare menu manuale/casuale, disattivazione, difficoltà, limiti posti;
   far scegliere l'Avatar una sola volta sull'host e sincronizzare client.
   Verificare snapshot costruito/applicato, privacy (nessuna identità nascosta),
   conteggi e round online. `AvatarState.network_public` è solo vista client.
10. Run regressioni, test pack Web e almeno playtest visivo. Solo dopo cambiare
    `implemented` a true, esportare nuovamente e aggiornare documentazione.

## Verifiche al momento del passaggio

- Godot 4.7.2 reale eseguito, non solo analisi statica.
- Prima dell'ultimo gruppo di integrazioni: regressione presentazioni/Heka,
  156 controlli, zero fallimenti.
- Dopo integrazioni Avatar/menu/board: `docs/handoff-2026-10-18/checks/avatar_smoke.gd`,
  41 controlli, zero fallimenti, log nella sottocartella `evidence/`. Un errore di parser
  sulla costante PackedVector2Array della plancia è stato corretto.
- `git diff --check` senza errori (solo avviso CRLF/LF su file esistenti).
- I risultati aggiornati sono in `docs/handoff-2026-10-18/VALIDATION.md`.
- Nessuna prova completa online con due PC e nessuna certificazione di Possessed.
- La build Web in `output/web/` è l'ultima build precedente all'Avatar, NON contiene
  le integrazioni attuali. Sorgenti e build hanno deliberatamente stati distinti.

## Modifiche precedenti da preservare

Heka pronta (9 scuole selezionabili con materiale completo), correzioni stanze
alternative e equivalenza Quest, Bibliotheca shift-click, Equipment non modelli,
evocations portraits, animazioni Spell/Trap/Protection e Power, attesa del click
per Spell pubblica, autorizzazione ack online, aggiornamenti relay/hosting/TLS.
L'utente ha rinominato Power of the Ankh: file corretto
`assets/spells/power_of_the_ankh.png`; il vecchio `power_of_ankh.png` è cancellato.
Non ripristinarlo.

## Motore e strumenti

Godot 4.7.2 stable Windows, con template Web nothreads per esportare.
Non cambiare versione incidentalmente. Progetto principale `main_menu.tscn`;
`game.tscn` è la partita. Il rendering Compatibility può essere passato da CLI
per GPU laptop senza cambiare `project.godot`.
I controlli prima temporanei sono ora in `docs/handoff-2026-10-18/checks/`:
conservarli per la ripresa, senza aggiungere patch usa-e-getta alla radice.
`docs/` è esclusa dall'export. Il verificatore PowerShell accetta il percorso
del motore con `-Godot`, senza dipendere dal vecchio nome utente.

HEAD di partenza: `fd89eb7dcd10ed28bc445528b7416f1036782f6c`, branch `master`.
Nessun commit nuovo o push è stato creato. L'utente sincronizza i file: assicurarsi
che sincronizzi anche i nuovi `avatar_*.gd`, JSON, asset e documenti di handoff.
GitHub trasferisce solo ciò che viene incluso nei commit/push dell'utente.

## Preferenze e vincoli conservati dalla chat

- Proseguire autonomamente; non fermarsi a una proposta quando è autorizzata
  l'implementazione. Non creare commit o effettuare pubblicazioni non richieste.
- Fedeltà al regolamento/FAQ e alle carte; in caso di testo ambiguo verificare
  la fonte. Non dedurre un effetto dalla sola illustrazione.
- Interfaccia da gioco da tavolo, playmat, nessun click che attraversa mano,
  menu o overlay; carte leggibili, non ridotte per far entrare tutto.
- PlayerBoard aperta dal banner laterale. Turno evidenziato sul banner; niente
  grande barra descrittiva degli effetti in alto. Carte lanciate a tutto schermo
  con click per continuare e lato attivo evidenziato; Trap/Protection settate
  mantengono privacy, animazione del token sulla PlayerBoard.
- Power token animato; quando avanza BR breve focus della PowerBoard. Movimento
  token visibile con scorrimento, Room attivata in sovraimpressione chiudibile.
- Quest risolte coperte; selezioni delle proprie Quest dalla scheda mano/Quest.
- Equipaggiamenti non sono modelli. Evocations normali NON vengono rimosse per
  sconfitta del Mage; solo quelle assegnate. Sostituzione al limite di 3 slot
  non conta come rimozione ai fini dei trigger.
- Stanze alternative equivalenti alle base ai fini delle Quest e sostituibili
  solo alla corrispondente. Life Fountain sostituisce Treasure Room;
  Indoor Forest sostituisce Garden. Apocalypse/Rebirth: grafica pronta,
  modalità specifiche rinviate su scelta esplicita dell'utente.
- Scuole selezionabili solo con tutto il materiale pronto; sul tavolo mostrare
  solo quelle attive. Le personal Spell non fanno parte dei mazzi scuola.
- Simboli corretti Sacred/Profane/Magic/Mage/Self/Persistent; Dark Omens è
  Profane su entrambi i lati come da conferma esplicita dell'utente.
- Utente aggiunge molte PNG: non rinominare asset senza controllare riferimenti.
- La vecchia chat conteneva numerose segnalazioni già affrontate: non riapplicare
  indiscriminatamente vecchie patch. Codice e documenti datati in `docs/` sono
  la base per verificare lo stato effettivo.

## Perché questi file bastano per la nuova chat

Il punto di ingresso è `RIPRENDI_QUI.md`, richiamato da `AGENTS.md` con la priorità
aggiornata. Questo conserva obiettivo, fonti, decisioni, stato e prossimi passi
senza dipendere dalla cronologia della chat. L'uso di AGENTS.md e documenti di
contesto è descritto anche nella [documentazione ufficiale OpenAI](https://developers.openai.com/cookbook/examples/codex/iterating-development-workflows-with-codex).
