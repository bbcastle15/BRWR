# Verifica della ripresa — 18 ottobre 2026

## Ripresa 19 ottobre 2026

### Avatar Board e carte HD

Ricostruite 47 carte HD, caricate tutte con lato minimo 1024 px. Originali
conservati; prompt e generatore descritti in `docs/AVATAR-HD-ARTWORK.md`.
Il runtime preferisce HD ai vecchi ritagli atlas.

Avatar non istanzia più una PlayerBoard: la stessa AvatarBoard sul tabellone
si apre nel modal e torna nella propria posizione alla chiusura. Carta Avatar,
mazzo/reazione, Memories sfogliabili, Evocations I–III, traccia danni, Quest
risolte coperte, assegnazioni e Jinx sono consultabili dalla board dedicata.
Nessuno stato di gioco duplicato nel renderer.

Book of Nature corretta da verde a grigio confrontando lo screenshot Moon 1.
Suite `avatar_movement.gd`: 8 controlli passati (Speed 2, arrivo in stanza
grigia a distanza 2, scelte in parità al proprietario della Corona).
Suite `avatar_board_ui.gd`: prima verifica 9 controlli passati, oltre a
catture reali OpenGL Compatibility per board, scarti e tavolo.
Suite `avatar_layouts.gd`: 25 controlli passati sui 5 layout da 2 a 6 posti;
viste acquisite e ispezionate. Include conservazione della trasformazione
nel modal dopo refresh del layout.

Regressione completa successiva: smoke Avatar 41, regole 144, flow 46,
Protections 29, movimento 8, board 9, menu (selezione/limiti/disattivazione),
presentazioni 156, playtest 115, scuole 56, stanze 134 e UI stanze 25:
nessun fallimento o errore di script. Import e 13 JSON validi.
Log della regressione in `evidence/2026-10-19-avatar-board/`.
Il test finale della board, esteso al targeting dei cubi danno, passa
**10 controlli**, senza errori di script (`evidence/avatar-board-final.txt`).
Nessun test online reale su due PC o nuovo export Web in questo blocco.

### Implementazione Protections umane

Riprodotti e corretti due difetti nel runtime Avatar: Bone Shield non riceveva
il contesto in `event.data`; le reazioni non annunciavano gli effetti ostili
e quindi non consentivano Caput Draconis Dark. Ora entrambi i percorsi
riusano la finestra ordinaria dei trigger e il contesto della sezione.
Gli effetti puramente difensivi dell'Avatar non espongono falsi bersagli umani.
La nuova suite `avatar_protections.gd` passa 29 controlli, inclusi area,
conversioni, scarti, risposta Bone Shield e isolamento fra Comandi.
Regressione completa successiva alle correzioni: **746 controlli superati,
zero fallimenti**, import Godot e 13 JSON validi. Log conservati in
`evidence/2026-10-19-protections/`. Nessuna verifica visiva o partita online
reale eseguita in questo blocco; Avatar rimane disabilitato.

Verificatore completo `-Suite all` terminato con successo: **717 controlli,
zero fallimenti**. Ripartizione: smoke Avatar 41, regole Avatar 144, flow 46,
presentazioni/Heka 156, playtest 115, scuole 56, stanze alternative 134,
UI stanze 25. Log completi conservati in `evidence/2026-10-19/`.

Eseguiti con Godot 4.7.2.stable.official.ed1daf0bf i test isolati
`avatar_rules.gd` (144 controlli) e `avatar_flow.gd` (46 controlli):
nessun fallimento. Evidenze in `evidence/avatar_rules.txt` e
`evidence/avatar_flow.txt`. Il flow controlla anche snapshot serializzato e
applicato a un client, senza identità o ordine del mazzo nascosto.

Correzioni alla suite: rinominato `Projection`, in conflitto con un tipo
Godot; azzerato il Potere umano nel solo scenario del Comando aggiuntivo
senza cambio Luna. Il cambio Luna immediato ha uno scenario separato.
Non sono state cambiate regole del gioco per adattarle ai test.
Il verificatore include ora entrambe le suite e usa log espliciti scrivibili.

Import editor riuscito fuori dalle restrizioni del processo; nella sandbox
l'editor falliva il salvataggio delle impostazioni locali. JSON: 13 validi,
ID Avatar univoci e riferimenti atlas presenti. Rimangono necessari collaudo
visivo e prova online reale. `implemented` resta `false`.

## Verifica precedente

Eseguito il verificatore portabile `Verify-Resume.ps1 -Suite smoke` sul progetto
corrente, con Godot **4.7.2.stable.official.ed1daf0bf**.

Esito:

- Import editor/headless concluso senza errori di script o parser.
- Tutti i **13 JSON** nella cartella `data` validi sintatticamente.
- ID univoci nei tre cataloghi Avatar; tutti i file immagine referenziati
  dall'atlas Avatar presenti.
- **41 controlli** dello smoke test Avatar superati.
- **156 controlli** presentazioni/Heka superati sul codice corrente.
- `git diff --check` senza errori di whitespace; Git segnala soltanto la
  normalizzazione CRLF/LF già prevista per alcuni file.

Evidenze testuali conservate in `evidence/import.txt`, `avatar_smoke.txt`,
`presentations.txt`, `resume-validation.txt`. I percorsi assoluti presenti nei
log descrivono il PC su cui sono stati eseguiti; gli script non dipendono da essi.

Questi risultati dimostrano importabilità e assenza delle regressioni coperte
dai controlli eseguiti. NON dimostrano il completamento della modalità Avatar:
sono ancora necessari i test specifici elencati nel passaggio di consegne,
la revisione visiva della plancia, il playtest completo e la prova online.

`data/avatars.json` mantiene `implemented: false`. Non è stata prodotta una
nuova build Web delle modifiche Avatar. Nessun commit o push automatico.

Il trasferimento Windows su un secondo PC non è stato materialmente eseguito;
il contesto necessario è salvato nel repository per la sincronizzazione utente.
## Ultimo collaudo — correzioni playtest Avatar del 19 ottobre

Godot 4.7.2 stable: `Verify-Resume.ps1 -Suite all` completato con successo.
13 JSON validi; import/editor senza errori; 47 immagini ad alta risoluzione
caricate; controllo menu superato. **790 asserzioni** complessive superate:
Avatar smoke 41, regole 144, flusso 46, protezioni 29, movimento 8,
board UI 10, correzioni playtest 26, presentazioni 156, regressioni 115,
scuole 56, stanze alternative 134, UI stanze alternative 25.

Il test `avatar_playtest_fixes.gd` è stato eseguito anche con renderer grafico:
26 asserzioni senza errori. Ispezionate le catture `avatar-portrait-fixed.png`
e `upgrade-grid-fixed.png`. Log della suite completa copiati in `evidence/`
come `*.log`; log grafico `avatar-playtest-visual-final.txt`.

Copertura nuova: verticale della board/carte, cubi sulle Evocations,
targeting ruotato, movimento animato con Lodge visibile, griglia Upgrade,
scelta Corona effettivamente completabile tramite stanze evidenziate,
attivazione Forgotten senza stanza preliminare, Command fisico e rifiuto
di 6 umani più Avatar prima di creare una sessione online.

I 15 Eventi e Possessed sono restauri generativi dagli screenshot originali,
con correzioni localizzate dei simboli. Prompt in `restored/provenance.json`
e `restored/corrections.json`. Non sono copie pixel-identiche: rimangono
differenze nei glifi, nelle decorazioni e in parte dei codici editoriali.
Il test HD verifica soltanto caricamento e risoluzione, non fedeltà grafica.
Nessun salvataggio della partita bloccata era disponibile: verificato il
percorso equivalente di scelta della Corona, non quella partita specifica.
La prova online tra due PC e un'intera partita manuale restano non eseguite.
## Secondo playtest — materiali e memorie, 19 ottobre

`Verify-Resume.ps1 -Suite all` completato con Godot 4.7.2: **813 asserzioni**
senza fallimenti, oltre a controllo menu, 47 texture caricate e 13 JSON validi.
Log della suite `BRWR-resume-20261019-160150-92fe04` copiati in `evidence/`.
La nuova suite `avatar_publication.gd` contribuisce 23 verifiche e riproduce
la consultazione delle memorie durante Preparation fino alla conferma delle
due spell preparate. Controlla inoltre tre retri, Destino/Infectio, colore
dell'ultimo danno, plancia vettoriale e targeting delle Evocations dal Lodge.

Dopo le ultime rifiniture esclusivamente grafiche: import completato senza
errori (`avatar-materials-complete-import.txt`), collaudo grafico con tutte
le 23 asserzioni superate (`avatar-materials-complete-visual-v2.log`). Ispezionata
la cattura `avatar-production-board.png`, incluse numerazione, contorno vita,
marker e retri. Ispezionati i nuovi simboli originali estratti dal regolamento,
facce rappresentative dei Comandi/Eventi e correzione Raging Lash.

Le facce sono ricomposte tipograficamente con i glifi originali: cornici e
materiali sono ricostruiti e non copie pixel-identiche delle fotografie.
Sfondi illustrati e retri generati con ImageGen, testo/simboli/valori composti
separatamente. Prompt in `production/*provenance.json`; font intermedi
esclusi dal runtime. Nessun nuovo export, commit o prova online tra due PC.

## Terzo playtest del 19 ottobre — stato finale

Suite completa: **837 asserzioni**, 0 fallimenti, oltre a menu, caricamento
47 carte e 13 JSON. Log `evidence/third-playtest-*.log`, import incluso.
Nuova suite `avatar_jinx_playtest`: 24 asserzioni; anche esecuzione grafica
finale, exit 0 e nessun errore (`avatar-jinx-final-visual.log`).
Verificate visivamente `anubis-actions-centred.png`, `avatar-visible-jinxes.png`
e la presentazione delle Jinx. Corrupted Spear percorre 2 stanze con Speed 2,
una con Slowness, dopo una vera scelta della Corona fra stanze blu equidistanti.
La sequenza di assegnazioni riprende dopo la presentazione senza duplicazioni.
FAQ ufficiale v1.2 p.6: Vulnerability non infligge danno alla propria assegnazione.

**Il requisito artwork HD fedele resta incompleto.** Le facce ricomposte sono
state rifiutate dall'utente. Anche i nuovi tentativi generativi alterano simboli;
non sono in runtime (`faithful/.gdignore`). `AvatarArt` ripristina le 46 facce
originali dall'atlas: nessuna nuova cornice, ma la risoluzione rimane quella
degli screenshot. Il controllo asset certifica identità della fonte/caricamento,
NON qualità HD. Non chiamare questo stato pronto per pubblicazione.
Nessun export, commit o prova online fra due PC in questa sessione.
