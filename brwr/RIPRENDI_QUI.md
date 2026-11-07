# Ripresa 7 novembre 2026 — Agony, Entropy e Cursed Hieroglyphics

Il playtest segnalato comprende Cross and Delight Light, Peak of Agony Dark, due copie di Entropy Dark e una Cursed Hieroglyphics scattata durante Explore. Il controllo dedicato è `docs/handoff-2026-10-18/checks/nov07_spell_reactions.gd`. Riutilizza i lanci, le finestre delle trappole, i danni e gli spostamenti effettivi del motore.

- **Pain.** Il Codex specifica che la Rosa Nera infligge il danno al lanciatore. Il pannello deve permettere al proprietario di scegliere esplicitamente il proprio mago o una delle proprie evocazioni idonee. Il log deve nominare il mago. Per Cross and Delight la stanza selezionata determina dove compare il Succubus e il Succubus appena evocato si attiva dopo Pain.
- **Peak of Agony Dark.** Il secondo simbolo nel testo è Model a distanza 1 dal primo bersaglio. Vanno esclusi il lanciatore e il modello già scelto. L'effetto usa il selettore dei modelli e il danno proporzionale esistenti. Verificare sia due maghi distinti sia un'evocazione.
- **Entropy Dark.** La copia passata resta armata per i successivi colpi letali idonei. Nota sulle fonti: la FAQ inglese del 28 gennaio 2026, errata a pagina 21 del regolamento, attribuisce il danno di un'evocazione al modello evocazione anche quando i cubi hanno il colore del controllore. Lo stato del mago al momento della risoluzione può differire da quello al piazzamento dell'ultimo cubo.
- **Cursed Hieroglyphics.** Entrambi i lati colpiscono la stanza rossa o verde e pescano una Jinx per ogni altro mago che vi si trova dopo i danni. Il Codex a pagina 32 specifica il trattamento dell'omonima già assegnata. Il log condiviso deve distinguere l'assegnazione dalla pesca di un duplicato o dal mazzo esaurito.

# Ripresa 6 novembre 2026 — Fountain of the Three Dark e cubi coperti dalle Umbre

Il commit del laptop è `418b4ad` (`updates laptop`). Comprende la rivelazione anticipata delle carte pubbliche via WebSocket, i ritratti Umbra più piccoli con bordo nero, l'apertura della plancia per Destino e conversioni sui maghi, 43 fronti Quest restaurati e le 12 Hex approvate. I dettagli del 5 novembre sono nella sezione successiva. La versione di **Conspirator Mage** approvata dall'utente è `assets/quests/reconstructed/conspirator_mage.png`.

**Fountain of the Three, Dark.** Il riferimento è il testo stampato in `assets/spells/fountain_of_the_three.png`. Il lato Dark indica per primo l'Enhancement Aria. In `data/spells.json` ora usa l'ordine già supportato dal motore, `enhancement` seguito da `base`. Se il mago soddisfa il requisito, piazza 1 Instabilità nella stanza bersaglio prima della domanda «Activate a Construct / Summon a Nigredo». Senza Aria si arriva direttamente alla scelta. La verifica osserva i cubi **nell'istante in cui il motore richiede la scelta**, oltre a controllare lo stato finale di entrambe le alternative.

**Conversione del Danno.** Le Umbre assegnate condividono l'origine grafica del token del mago. I vecchi cubi creati accanto ai token si sovrapponevano nella Loggia.

- Per le evocazioni, `game.gd` collega la scelta al cubo raffigurato sulla carta nello slot corretto della PlayerBoard o sulla plancia di Possessed. Per il mago usa la traccia Danno. Le opzioni pubbliche identificano la plancia e l'evocazione e l'host convalida ogni cubo.
- Se una conversione di stanza comprende più plance, il pulsante **View … ›** passa alla successiva. I cubi scelti restano selezionati fino alla conferma.
- Per l'Instabilità si clicca direttamente la casella della stanza. Durante la scelta il cubo e la sua area cliccabile hanno la precedenza sui token dei modelli. Il gioco rimuove l'evidenziazione quando il giocatore ha finito.

**Come verificare sul laptop.** Dalla cartella di `project.godot`, avviare l'eseguibile console di Godot 4.7.2 con gli argomenti seguenti.

- `--headless --path . --script res://docs/handoff-2026-10-18/checks/nov04_quest_triggers.gd` verifica la sequenza di Fountain.
- `--headless --path . --script res://docs/handoff-2026-10-18/checks/nov04_playtest.gd` verifica i click su plance giocatore e Avatar usando due istanze e il protocollo host–client serializzato.
- Per il playtest su due PC, preparare una stanza con due Umbre ferite assegnate allo stesso mago e un altro bersaglio ferito. Convertire il cubo della seconda Umbra e verificare il suo colore su entrambi gli schermi.

**Esito del 6 novembre con Godot 4.7.2.** Sono passati 48 controlli Quest/trigger/Fountain, 119 controlli di playtest host–client, 25 di interazione con le stanze e gli Equipment, 10 della plancia Avatar e 38 Jinx/Nightmare. Fra i casi esercitati ci sono tre Umbre dello stesso mago, uno snapshot ricevuto durante una selezione multipla, il secondo di due cubi dello stesso colore su Colossus e una casella della Black Rose Room coperta fisicamente dal ritratto Umbra. Alla chiusura del test host–client headless Godot segnala risorse del renderer di test ancora in uso. Anche eseguendo la versione precedente dello stesso test si ottiene lo stesso avviso.

**Versione Web locale.** Rigenerati `output/web` e `deploy/web_bundle`. Il pacchetto ha passato il test di avvio e il confronto sorgente/export su 239 texture Spell, 57 carte Mago, 49 Quest e 108 impronte di codice o risorse. Per gli atlanti il confronto usa i pixel del ritaglio effettivo, le coordinate e le impostazioni di campionamento, anche quando Godot compila il file di testo `.tres`. Chrome ha caricato WebAssembly e PCK fino al menu principale. Entrambi gli archivi sono stati ricomposti da sette parti e verificati.

| Archivio | Byte | SHA-256 |
| --- | ---: | --- |
| `index.pck` | 225346928 | `d5c33461923452783da6ab02167a48094f14c309b25a1e7f6630f9f8302c7e4d` |
| `index.pck.gz` | 222462342 | `eaf4196e19bada14e29f00f478d96f7f0dd2d29676324faf19cb319ab71af225` |

Il bundle è pronto per la prossima pubblicazione. Resta da provare la partita su Internet con due PC.

# Ripresa 5 novembre 2026 — comparsa delle carte e bordo Umbra

Quando l'host rivela una carta pubblica, invia subito il messaggio WebSocket `card_reveal` prima del caricamento locale dell'immagine e della sincronizzazione completa. Il client mostra la carta alla ricezione, a piena opacità. La conferma continua a usare il numero di presentazione dell'host. Il bordo dell'Umbra è nero sia sulla mappa sia nelle copie usate per le animazioni.

Controlli Godot con trasporto simulato e serializzazione del protocollo esistente: 23 verifiche online passate, inclusa la comparsa sul client prima dello snapshot. Altre 38 verifiche Jinx/Nightmare passate, compreso il colore del bordo nelle tre posizioni. Per misurare la latenza della connessione reale occorre una partita su due browser. Il nuovo pacchetto richiede host e client della stessa versione.

# Umbra, Destino e versione Web

Ridotto il raggio del ritratto Umbra da 28,71 a 17. Il ritaglio lascia cliccabile il mago. Il settore considera i token presenti nella stanza. La logica di zoom ora gestisce anche i token con ritratto che non hanno un badge numerico. La stessa geometria è condivisa dal Famiglio agganciato.

Il menu fisico offre Activate Evocation con il nome. Hide chiude il pannello aperto. La scelta Destino apre la plancia della vittima e identifica il proprietario dell'ultimo cubo. Per una conversione di danno viene aperta la plancia del bersaglio e le alternative su altri modelli restano nel menu. Il retro Avatar semplice di Luna II è stato corretto con la mezza luna argentata. Emet-Met Dark consente di selezionare il proprio Nigredo. Explore costruisce i percorsi dalla velocità effettiva, inclusa Slowness in cella.

Verifica Godot 4.7.2: 30 controlli Quest/trigger e regressioni di questo passaggio, 32 controlli Jinx/Nightmare, tutti superati. Riprodotti la selezione di Nigredo, i percorsi da una cella a velocità 1, la destinazione delle richieste Destino/conversione e il cambio zoom senza badge.

Rigenerati `output/web` e `deploy/web_bundle`. Verifica del pacchetto superata, compreso il confronto dei pixel di 43 Quest, due retro e 12 Hex fra sorgente ed export. Manifest SHA-256 dei due file divisi in sette parti ciascuno in `docs/handoff-2026-10-18/evidence/nov05-quest-web-bundle.json`. Nessuna pubblicazione online. Per il prossimo playtest verificare a due browser la sequenza attacco letale, Destino, conversione e chiusura, oltre alla leggibilità dell'Umbra in una stanza affollata.

# Quest delle tre lune

Il gioco carica i 43 fronti restaurati corrispondenti agli screenshot da `assets/quests/restored/`. I retro della seconda e terza luna sono in `assets/quests/backs/`. La prima luna usa la scansione originale. Le sei Quest del catalogo prive di nuovi screenshot continuano a usare le rispettive fonti precedenti.

Confrontate le 18 Quest fornite che riportano Instabilità. Il disco Instabilità (e904) e il simbolo Contingency hanno funzioni distinte. Su Channeling Instability il disco compare una volta nel requisito e due volte nella ricompensa. Contingent Mage usa Contingency nel requisito e Instabilità nella ricompensa. Corrette anche Elementalist e Power Catalyst. Per risalire ai riferimenti e alle correzioni consultare `assets/quests/production/`, in particolare `nov05_instability_review.json` e `nov05_other_glyphs.json`. Le 12 Hex approvate passano da `assets/spells/hex_reviewed/`.

Allineati i centri dei cubi ai nuovi fronti. Elementalist, Deep Knowledge e Power Catalyst mostrano quattro spazi stampati. Master of Death assegna un trofeo per ciascun mago scelto. Vital Sun mantiene l'ID preesistente `vial_sun`.

Test Godot `docs/handoff-2026-10-18/checks/nov04_quest_triggers.gd` superato, 26 controlli. Nella riproduzione di Bad Luck due copie consumano due e poi un cubo nella Forge, lasciando intatta l'instabilità nell'altra stanza. Rimangono da riprodurre in una partita a più client la catena storica completa con Weighing of Souls, Sarcophagus e Torment e da controllare a schermo Jinx, trofei e classifica finale.

---

# Storico del 4 novembre 2026 — correzioni glifi, batch Quest da verificare

Ultime annotazioni corrette con image_gen e salvate in assets/quests/restored:
Pyromancer: dopo draw 1 sostituita la sfera con il simbolo Spell Card e905;
Master of Death: trofeo nel premio, danno nel requisito, BRW nel codice;
Wise Moon: bersaglio Self; Warrior Wizard: Evocation *;
Summoner: Evocation *, Nigredo, Room *, BRW nel codice;
Earth Tempest: rimosso 2 aggiunto fra and/or e Air.
Anche Contingent Mage, Shattered Illusion e Magic Steam hanno versioni
corrette salvate. Prompt e sorgenti: production/nov04_glyph_corrections.json.
Il resolver Quest gia privilegia restored. NON dichiarare l'intero mazzo pronto.

Batch di 41 immagini conservato in assets/quests/production/candidates,
con prompt/sorgenti in nov04_generated_manifest.json. Queste sono CANDIDATE
NON verificate: molti simboli generati erano sbagliati. Confrontare ogni
carta con gli screenshot production/references prima di promuoverla.
I due retro sono fra le candidate, ancora non collegati. Vital Sun usa nel
database lo stable ID vial_sun; verificare anche i suoi premi con la fonte.
Allineare progress_centers dei nuovi PNG (attualmente solo metadata Atlas).

Hex: copiate le 12 review approvate in assets/spells/hex_reviewed;
An Eye for an Eye sostituita con versione Power corretta. SpellArtResolver
ora privilegia questa cartella rispetto agli alias precedenti.

Codice modificato in corso: Elementalist conta spell_resolved con elementi
Fire/Earth/Water/Air; Ineluctable Pain riconosce Evocation della Rosa Nera;
attacco Evocation->Mage passa dall'animazione; Jinx progress overlay nei
riquadri stampati; Chaos theme; banner nascosto con scelta aperta;
trofeo z_index 200; tabella finale; token Umbra/Familiar con ritratto
circolare e taglio concavo (shader attached_portrait).
Test gia eseguiti: nov04_quest_triggers 17 controlli PASS;
nov03_jinx_nightmare 32 assertion PASS. Questi NON provano parita Web
o correttezza completa delle catene annidate. Restano da verificare:
conversione Bad Luck end-to-end e catene trigger; visual QA token/Jinx/
tabella finale; tutte le candidate Quest; preservazione lossless nell'export;
parity test (ha conteggio originali hardcoded 13 da aggiornare); export Web.
Web NON rigenerato dopo questi cambiamenti. Nessun commit/push/deploy.

---

# Ripresa precedente — Holy Corruption e contesto trigger

Nuove fonti Quest ad alto zoom ricevute (43 fronti, retro Moon II e III).
Richiesta attuale: restaurare fedelmente tutte queste carte, conservando i
simboli. NON usare build_quest_faces.py o ricomposizioni dal JSON.
Holy Corruption restaurata tramite image_gen; dopo la segnalazione dei due
simboli sbagliati, sostituiti Sacred/Profane e le ripetizioni inferiori con
i glifi ufficiali e96a/e969 come riferimenti. PNG in
assets/quests/restored/holy_corruption.png (1024x1536); resolver privilegia
restored, poi originali. Le altre Quest NON sono ancora restaurate.

Bad Luck: instability_placed valorizzava solo source_room_id, mentre il
trigger event_room leggeva target_room_id vuoto. Aggiunta destinazione
all'evento e fallback source per eventi preesistenti. Inoltre i valori
identificativi del trigger corrente prevalgono sul contesto salvato della
spell (evita riuso di triggering_player/room/amount precedenti).
Nightmare: richiesta slot ora specifica Player N della plancia destinataria.
Test nov04_quest_triggers.gd: 9 controlli, 0 errori; import senza errori
GDScript (solo errore ambiente salvataggio editor settings a path vuoto).
Export Web NON rigenerato in questo passaggio; nessun commit/push/deploy.

Restano aperti dalla richiesta corrente: altre Quest e due retro; sostituire
Hex light_review dopo correzione An Eye for an Eye dark Air -> Power;
token Umbra/Heracleto circolari con taglio concavo; Chaos box; verifica FAQ
Ineluctable Pain/Umbra; cubi progresso Jinx; audit completo catene trigger;
Elementalist (anche elementi JSON divergono dalla fonte Fire/Earth/Water/Air);
attacco Evocation->Mage; sovrapposizione box; livello animazione trofei;
tabella vittoria. Non dichiarare questi punti completati.

---

# Quest artwork — 4 novembre 2026, originali Moon I collegati; HD da completare

Arrivata tavola originale 973x831 con 14 fronti Moon I e relativo retro.
Fonte conservata integralmente in assets/quests/production/references/moon_1_original.png.
Manca solo Conspirator Mage (non due carte). I due tentativi ImageGen su
Holy Corruption hanno alterato simboli/cornice: RIFIUTATI, NON usarli nel gioco.
Per rispettare la richiesta, usare AtlasTexture degli originali in
assets/quests/originals: ritagli dichiarativi, pixel invariati, niente riscrittura.
Non chiamarli HD: ogni carta nella fonte misura circa 176x265 pixel. Servono
fonti più grandi per maggiore dettaglio fedele. Retro Moon I in assets/quests/backs.
Conspirator Mage è una ricostruzione autorizzata separata in
assets/quests/reconstructed/conspirator_mage.png, contenuto verificato col JSON,
approvata dall'utente per il gioco. Le altre Lune in quel passaggio erano invariate.
Collegati originali e retro Moon I a preview/mazzo/Quest risolte; cubi
posizionati sulle caselle misurate nella fonte. Verificati tutti i ritagli
con screenshot OpenGL in assets/quests/production/review. Field Test aveva
nel JSON tre caselle e target Mage; l'originale mostra due e Model: corretti
i due valori, passati nove controlli runtime (progressione e danno Evocation).
Parser e baseline sorgente passati. Export Web e bundle locale aggiornati:
parità PASS per 239 Spell, 57 Mage, 49 Quest e 65 hash codice/risorse; pixel
dell'atlante originale identici fra nativo e Web. EXPORTED PACK CHECK PASS.
PCK 109266724 byte, gzip 106406430 byte, quattro segmenti da max 32 MiB
ciascuno, SHA-256 concatenati verificati. Manifest nov04-quest-web-bundle.json.
Segmenti *.part* marcati binary in .gitattributes per evitare normalizzazioni Git.
tools/build_web_render_optimized.ps1 preserva lossless e dimensioni delle
Quest originali. Report docs/QUEST-ART-2026-11-04.md. Rimane il limite della
fonte: richiedere screenshot più grandi per restauri più dettagliati delle carte fornite.
Preservare ogni modifica precedente; nessun commit/push/deploy.

## Verifica precedente

Nuova istruzione esplicita: le Quest devono essere restauri delle immagini
originali, preservando proporzioni, grafica, impaginazione, testo e simboli.
NON ricomporre le carte da data/quests.json, NON reinterpretare i glifi,
NON usare tools/build_quest_faces.py per produrre le nuove versioni.
L'utente ha rifiutato le ricostruzioni attualmente mostrate nel gioco.

Verificati assets/quests, assets/quests/symbols, materials, riferimenti docs,
20 clipboard PNG ancora presenti in Temp e cronologia Git delle Quest.
Le PNG in assets/quests sono già ricostruzioni, non gli screenshot originali;
symbols contiene la ricomposizione dal JSON del 3 novembre. Non sono fonti
valide per il restauro richiesto. La ricerca testuale nel Codex non ha
identificato le carte cercate.
Gli screenshot originali delle Quest non sono stati ritrovati. Richiedere
all'utente di allegare nuovamente i fronti, anche a gruppi, prima di generare.
Questa verifica non ha modificato runtime, immagini, JSON o build Web.
Quando arrivano i riferimenti, conservarli integralmente nel progetto e
produrre versioni HD da ciascuna immagine, confrontando tutti i simboli.

---

# Playtest — 4 novembre 2026, cinque correzioni concluse

Richiesta corrente: Waiting errato durante rimozione Evocation; Umbra sotto
la carta dello slot assegnato (affiancata su Possessed); banner cambio Moon;
AvatarBoard visibile mentre altri confermano Damage; anello proprietario
preservato nell'animazione di attacco Evocation. Conservare il lavoro precedente.

Correzioni applicate a game.gd, tabletop_shell.gd, player_board.gd,
avatar_board.gd, evocation_token.gd e umbra_token.gd. Cause individuate:
school_remove_models interpretato come pesca School nel Waiting; overlay
nascosto alla conferma locale con AvatarBoard ancora reparentata dentro;
ghost attacco privato dello script che disegna l'anello. Banner Moon usa il
feedback autorevole già trasmesso ai client, non una nuova sorgente di stato.
Umbra usa assigned_slot, non board_number; nessun cambiamento alle regole.

Codice concluso e 428 asserzioni passate: nov04_playtest 103 (OpenGL,
host/client, click reali Continue, Umbra e campione pixel dell'anello),
avatar_rules 135, oct29_avatar_reactions 99, nov03_online_animation 18,
nov01_playtest 73. Screenshot nov04-* verificati. Nessun errore di script;
il nuovo test segnala risorse/texture residue allo shutdown: non confonderle
con fallimenti delle asserzioni. Parser Godot valido; diff --check pulito.
Baseline export nov04-export-baseline.json creata, include evocation_token.gd.
Export Web 1024/0.67 e deploy/web_bundle aggiornati. Parità PASS: 239 Spell,
57 Mage Card, 49 Quest, 50 hash codice/dati e versione multiplayer uguali.
tools/check_web_export.gd passato. PCK 107948244 byte, gzip 105100816 byte;
quattro segmenti da massimo 32 MiB ciascuno, concatenazioni SHA-256 verificate.
Il controllo automatico ha bloccato la cancellazione di due vecchi segmenti;
risolto mantenendo quattro segmenti e rigenerandoli tutti, senza cancellazioni.
Manifest nov04-web-bundle.json; dettagli in docs/PLAYTEST-2026-11-04.md.
Nessun lavoro di questi cinque punti lasciato da implementare. Rimane da
verificare una partita completa fra PC reali via Internet. Bundle locale
pronto, NON pubblicato: nessun commit/push/deploy eseguito.
Log parser: %TEMP%/brwr-nov04-parser.log. Log originali del playtest conservati
in %TEMP%/BRWR-playtest-nov04-preserved. Nessun commit/push/deploy richiesto.

---

# Playtest online — 3 novembre 2026, modifiche concluse e bundle verificato

Applicata la lista di 19 punti. Priorità gestite: sincronizzazione dopo la
sconfitta/Cell, Cadaver spostato, ultima Instability e Damage Avatar. Aggiunta
pubblicazione delle proiezioni cambiate ogni 250 ms, deduplicata per peer;
Evocations remote identificate dall'istanza autorevole anziché dallo slot.
Ghost Damage sotto la plancia stabile; PB del nuovo viewer appena aperta
manualmente preservata durante il cambio turno. Log originali conservati in
%TEMP%/BRWR-playtest-nov03-preserved. Preservare tutte le modifiche precedenti.

Completati anche: intro Scuole più lenta con Continue obbligatorio, rimozione
Show cards, pulsanti laterali uguali, Momentum Stay fuori Cell, click sul token
Mage per azioni fisiche, retro Jinx/Upgrade HD, banner ogni Activation anche
consecutiva/Avatar, username obbligatorio e School accanto al Mage, niente
apertura automatica PB, Waiting espliciti, Destiny più grande e animato,
fallback Natural Invocation in Hand. Tutti i testi nuovi sono in inglese.

49 fronti Quest con glifi originali in assets/quests/symbols; vecchie PNG
preservate. Tool tools/build_quest_faces.py, manifest assets/quests/production.
Nuovi retro in assets/jinxs/back.png e assets/upgrades/back.png.

462 asserzioni passate: 21 online base, 18 animazioni host/client (incluso
Explore remoto dalla Cell dopo danno letale e click reale sul Cadaver spostato),
36 intro Scuole OpenGL, 72 UI/lobby OpenGL, 135 Avatar Rules, 99 Reactions,
8 Remote Avatar e 73 regressioni UI. Verificati 16 JSON, 49 hash Quest PNG,
parser/import Godot e sintassi del relay. Dettagli e limiti nel report sotto.
Controlli sorgente conclusi; output/web e deploy/web_bundle aggiornati,
ottimizzazione 1024/0.67. Parità PCK passata: 239 Spell, 57 Mage Card,
49 fronti Quest, 49 hash codice/dati e stessa versione multiplayer. Passato
anche tools/check_web_export.gd. PCK 107944532 byte, gzip 105099563 byte;
5 parti da massimo 24 MiB ciascuno, concatenazioni SHA-256 verificate.
Baseline, manifest bundle e controlli in docs/handoff-2026-10-18/evidence,
prefisso nov03-playtest-. Dettagli in docs/PLAYTEST-ONLINE-2026-11-03.md.
Nessun commit/push/deploy: il pubblico resta sulla versione precedente finché
il bundle non viene pubblicato. NON usare tools/publish_render.ps1 senza
istruzione esplicita: fa commit e push. Ultimo log build:
%TEMP%/brwr-nov03-playtest-build.log.
Non dichiarare l'esatto blocco del playtest riprodotto né una partita completa
su due PC: i test usano due Game e protocollo/codec reali nella stessa istanza.

---

# Estrazione iniziale scuole — 3 novembre 2026, completata

Nuova richiesta: animare l'estrazione delle sei scuole all'avvio partita.
Scelta una mescolata del mazzo con sei rivelazioni a cascata, circa 5.6 secondi,
con Skip animation / Esc / Space. `school_draw_presentation.gd` usa solo
active_school_ids già estratti: nessuna modifica a selezione, ordine o RNG.
Hook locale/host in start_game_flow; client da snapshot durante Setup, una
sola volta. Input Loggia coperto, feedback Avatar/fasi in coda fino alla fine.
Stile playmat e font titolo già presente nel progetto, copiato in assets/fonts
per renderlo esportabile (la cartella originale production è esclusa).
Test visivo `nov03_school_draw.gd`: 33 asserzioni passate (OpenGL), incluso
resize 720p, Skip reale e snapshot ripetuti. Regressioni: 18 Avatar marker,
8 Remote Avatar e 73 UI passate. Parser valido; artefatti e dettaglio in
docs/SCHOOL-DRAW-2026-11-03.md. Export e deploy/web_bundle aggiornati; parità
passata per 239 Spell texture, 57 Mage Card, 46 hash, versione multiplayer e
font titolo esportato. Passato anche tools/check_web_export.gd. Parti bundle
da massimo 24 MiB (PCK 5 / gzip 4), concatenazioni verificate SHA-256.
Evidenze: nov03-school-draw-export-baseline.json e nov03-school-draw-web-bundle.json
in docs/handoff-2026-10-18/evidence. Nessun commit/push/deploy pubblico; online
verificato tramite snapshot reali, non una partita completa su due PC.
Preservare il lavoro precedente, inclusi il limite Hyperion e le anteprime Hex.

---

# Ultime richieste completate — 3 novembre 2026

Nuove richieste: zoom sul piazzamento Protection/Trap Avatar; Pharaoh deve
contare i maghi con Jinx, non il numero di Jinx; Jinx pubbliche sulla PlayerBoard
accanto alle Completed Quests; abilitare Nightmare dopo verifica materiale.
Pharaoh ha già il conteggio corretto in ForgottenEvocations.bonus_strength:
verificato +1 per Mage, rimozione dell'ultima Jinx e parità host/client.
Nightmare ora supera is_school_complete, con alias throne_of_torns per
throne_of_thorns. Jinx in colonna pubblica accanto alle Completed Quests, con
Task e ispezione; la plancia si allarga senza sovrapporre la trasformazione.
Animazione Avatar: zoom 2.4x sullo slot Hand, piazzamento, pausa e ritorno;
Close resta davanti alla plancia ingrandita. Test visivo finale passato:
22 asserzioni Avatar marker e 32 Jinx/Nightmare/Umbra/Familiar con snapshot
host/client. Numero del giocatore spostato sotto l'anello Umbra per leggibilità.

Nel lavoro precedente aggiunti 31 maghi e le Personal tramite
tools/add_remaining_codex_mages.py. Smoke test nov02_mages.gd: 70 lati,
222 asserzioni, zero fallimenti; non equivale a convalida delle singole regole.
Hyperion/Burning the Sky è ANCORA INCOMPLETO e non selezionabile
(implemented:false, controllato da MageDatabase e assign_mage_to_player): serve il vero stato multi-modello
Myrmidones e il doppio profilo. Le regole BRWR sono nelle ultime pagine di
../materials/NAR_Hyperion_Rulebook_ENG.pdf. Agorix/Eracleto ha FamiliarRules,
con Guardia agganciata al token Mage, azione Familiar separata, danni ripartiti,
bonus di Caccia contro bersaglio senza danni e ritorno opzionale in cleanup.
Carta Eracleto estratta dal Codex p.68, senza alterazioni; ritaglio ritratto
dichiarato in portraits.json. Test nov03_mage_rules: 52 asserzioni passate,
inclusi Guardia/Caccia, sconfitta, Doll, Jotuns Vindar, Alice e limite condiviso
di Drums of War. Corretto l'ordine uscita/entrata stanza: la posizione è già
aggiornata quando parte la reazione di uscita. School integration: 56 passate.
Regressioni: 135 Avatar Rules, 99 Avatar Reactions, 73 UI, 8 Remote Avatar,
zero fallimenti. Parser Godot e JSON validi. Non dichiarare Hyperion finito.

Export finale e bundle aggiornati: 239 Spell texture, 57 Mage Card, 45 hash
di sorgenti/dati identici. Verificata anche l'uguaglianza della versione
multiplayer fra host nativo e pack esportato; il fingerprint include ora
mage_effects.gd e familiar_rules.gd. Passato anche tools/check_web_export.gd,
il controllo usato dall'avvio host. Aggiunti gli estratti originali del Codex
per le Personal di 15 maghi già esistenti: fallback, precedenza alle PNG utente.
PCK 97.99 MiB e gzip 95.30 MiB; bundle in parti da massimo 24 MiB (5 e 4),
hash SHA-256 della concatenazione verificati. Baseline e hash finali:
docs/handoff-2026-10-18/evidence/nov03-export-baseline.json e nov03-web-bundle.json.
Nessun commit/push/deploy pubblico. Nessuna partita completa su due PC;
test online effettuati con snapshot host/client reali.
Dettagli: docs/PLAYTEST-2026-11-03.md.
Restano Hyperion/Myrmidones e l'approvazione delle copie grafiche Hex;
non sovrascrivere le PNG originali con quelle in hex_light_review.

---

# Umbra, maghi mancanti e Hex — 2 novembre 2026, in corso

Richiesta corrente: Umbra a settori incastrati intorno al Mage; rendere giocabili
i maghi con Mage Card già presente; schiarire solo la grafica Light di Hex,
salvando copie da approvare. Preservare tutti i cambiamenti precedenti.

- Create 12 anteprime con ImageGen in `assets/spells/hex_light_review/`, escluse
  dall'import con `.gdignore`. `gallery.html` confronta originali e copie;
  `manifest.json` registra prompt e provenienza. Originali non sovrascritti,
  nessun riferimento runtime alle anteprime.
- Aggiunto `umbra_token.gd`: settore anulare 120 gradi, hitbox separata dal Mage;
  `game.gd` aggancia i token Umbra assegnati al token Mage per seguirne lo slide.
  Import/parser Godot passato; verifica runtime e snapshot online ancora da fare.
- Censiti 31 maghi mancanti e la seconda forma di Hyperion. Dati/Personal Spell
  verificati visivamente sul Codex pp. 68–82; implementazione ancora in corso.
  Le Mage Card sono già in assets/mages, manifest `docs/mage-art-2026-10-23/`.
  Le immagini sorgenti delle Personal sono nello stesso archivio `sources/`.
  Agorix richiede il Famiglio Eracleto (regole aggiornate `../materials/magister.pdf`);
  Hyperion richiede le regole BRWR nelle ultime pagine del NAR_Hyperion_Rulebook.
- Evidenze e pagine in `docs/umbra-mages-hex-2026-11-02/`. Web e bundle non ancora
  ricostruiti per questa richiesta. Nessun commit/push/deploy.

---

# Token Avatar — 2 novembre 2026, completato

Ultima richiesta: manca l'animazione del token Protection/Trap Avatar.
Riprodotte tre perdite del feedback in `nov02_avatar_marker_playtest.gd`:
il cambio viewer e le nuove richieste svuotavano la coda prima del piazzamento;
il primo snapshot client considerava il token già mostrato. Correzione in
`tabletop_shell.gd` e `network_projection.gd`: conserva/riprende il piazzamento
nelle transizioni automatiche; Close/Esc esplicito può saltarlo. Inoltre il
`player_token.gdshader` ignorava l'opacità della sfumatura: ora la rispetta.
Nessuna modifica a carte/regole/limiti Comandi; test Trap usa solo una proiezione
grafica sintetica, Possessed continua ad avere le sue Protection originali.

Superati 19 controlli mirati con rendering OpenGL (inclusi pixel dello shader),
99 Avatar Reactions, 73 UI del 1 novembre e 8 Remote Avatar: 199 asserzioni.
Aggiornati `output/web` e `deploy/web_bundle`, usato da `tools/render_unpack.sh`.
Bundle con quattro parti per PCK/gzip, massimo 24 MiB ciascuna; concatenazione
verificata SHA-256. Pacchetto Web verificato: 184 Spell, 57 Mage, 32 hash uguali.
PCK 95.16 MiB / gzip 92.60 MiB; originali preservati. Nessun commit/push/deploy.
Dettagli: `docs/AVATAR-TOKEN-ANIMATION-2026-11-02.md`. La versione pubblica
richiede ancora la pubblicazione del bundle aggiornato; test online tramite
snapshot host/client in Godot, non una partita completa su due PC.
Preservare tutti gli asset e le modifiche esistenti.

---

# Playtest e Hex — 1 novembre 2026, completato

Richiesta: abilitare Hex; ridurre pausa fra movimenti; svanimento evocazioni
rimosse; descrizioni scelte pubbliche simmetriche host/client; bordo lato Spell
preparata in consultazione; nome azione fisica durante flip; annuncio fasi;
finestra evocazioni curata; verificare Instabilità Tomb Reinforcements e blocco
Player 2 in Cell. Le modifiche sono applicate. Superati 73 controlli mirati
sia headless sia con rendering OpenGL, 135 Avatar Rules, 99 Avatar Reactions
e 8 Remote Avatar: 315 asserzioni distinte. Incluse prove del passaggio del
viewer, annuncio fase remoto senza duplicati e svanimento sul client.

Riprodotta e corretta una chiusura indebita: `_process` di TabletopShell
chiudeva la plancia appena aperta dal nuovo input quando cambiava il viewer.
Ora preserva la plancia della nuova decisione. L'esatto blocco della partita
segnalata rimane non riprodotto; Choices/F10 ricostruisce l'input autorevole.

Build Web finale aggiornata in `output/web` (94.74 MiB / gzip 92.18 MiB).
Parità riuscita con `evidence/nov01-export-baseline.json`: 181 Spell, 57 Mage,
31 hash identici, Hex giocabile e retro/token Avatar caricabili. Esportazione
ottimizzata 1024 / 0.67; PNG originali intatte. Nessun deploy pubblico.
Test principale: `docs/handoff-2026-10-18/checks/nov01_playtest.gd`.
Dettagli, file interessati e limiti: `docs/PLAYTEST-2026-11-01.md`.

Hex: nuove PNG presenti, incluse `cerebral_worm.png`; alias senza rinominare
`feverish_dream.png` e `suffococation.png`. Catalogo mantiene il controllo
condiviso di completezza. Il log reale è stato preservato in
`%TEMP%/brwr-nov01-user-session.log`: nessun errore di script, ultima richiesta
`action_activation_step` per P2. Tomb ha già `instability: true`; nel log il
Templarii era nella stessa stanza dell'Avatar e Bone Shield può prevenire il
cubo. Aggiunto messaggio pubblico per Instabilità prevenuta da Upgrade/Jinx.
Non dichiarare riprodotto il blocco originale senza evidenza: si verificano
turno in Cell, Momentum, riapertura delle scelte e snapshot host/client.

Preservare tutte le modifiche e gli asset dell'utente, oltre al lavoro Avatar
del 29 ottobre. Nessun commit/push/deploy.

Durante l'ultimo controllo Git sono comparse altre PNG dell'utente in
`assets/spells`: `hysterical_escape.png`, `persecution.png`,
`shifting_nightmare.png`, `throne_of_torns.png`. Preservate senza modificarle;
arrivate dopo l'esportazione finale, quindi non fanno parte della build Web
verificata sopra. Per il prossimo lavoro su Nightmare controllare anche
l'alias di `throne_of_torns` rispetto all'ID `throne_of_thorns`.

---

# Avatar: retro reattivi e token — 29 ottobre 2026, completato

Richiesta corrente: cinque retro HD Possessed (due carte condividono il retro di
Luna I), token Protection con cuore spezzato o fulmine, animazione di piazzamento,
verifica delle condizioni di pagina 38. Sette PNG generati con ImageGen e salvati
in `assets/avatars/possessed/approved/command_back_*_protection_*.png` e
`assets/tokens/avatar_protection_*.png`; prompt e provenienza nel manifest
`docs/handoff-2026-10-18/evidence/avatar-reaction-art-2026-10-29.json`.

Sorgenti aggiornati: `avatar_state.gd`, `avatar_art.gd`, `avatar_board.gd`,
`avatar_rules.gd`, `tabletop_shell.gd`. Proiezione pubblica del solo simbolo,
limite Comandi per il token, animazione sulla vera Avatar Board. Corretto il
trigger Combat che considerava anche gli effetti su una Room (FAQ Target of a
Spell); ricontrollo danni prima della reazione. Il token si posa sullo scudo
stampato, lasciando leggibili Luna e nome, e rispetta il limite dei Comandi.

**Dettagli:** [docs/AVATAR-REACTIONS-2026-10-29.md](docs/AVATAR-REACTIONS-2026-10-29.md).
242 controlli distinti superati: 99 sui nuovi retro/token e trigger (anche con
rendering), 135 sulle regole Avatar, 8 sulla regressione danni remoti/Hand.
Godot 4.7.2: import/parser e controllo del pacchetto Web superati. Build in
`output/web`: 178 texture Spell, 57 Mage card, 24 hash sorgenti corrispondenti,
cinque nuovi retro e due token caricabili. PCK 94,6 MiB / gzip 92,1 MiB;
export ottimizzato a 1024 px, qualità 0,67, originali HD preservati.

La verifica online usa snapshot host/client reali in Godot; non è stata
giocata una partita completa su due PC. Trasferire anche i file non tracciati
e `output/web`. Preservare `assets/spells/pact_of_the_jaws.png`, modificata
dall'utente prima di questo lavoro. Nessun commit/push/deploy.

---

# RIPRENDERE DA QUI — 28 ottobre 2026, revisione C / cambio computer

Ultima richiesta: danni di evocazione all’Avatar invisibili sull’altro client e Hand Web coperta dalla colonna sinistra. Corretti in `tabletop_shell.gd`: preservazione dei danni in attesa quando si apre Hand; CanvasLayer separato per la plancia ingrandita, colonna sempre sotto Hand.

**Passaggio dettagliato:** [docs/HANDOFF-2026-10-28-C.md](docs/HANDOFF-2026-10-28-C.md).

Il test di regressione riproduceva la perdita dei danni prima della correzione e passa dopo. I test sono nativi con snapshot host/client; la verifica finale in due browser resta da fare seguendo i passi del documento.
43 controlli mirati superati: 8 nel nuovo scenario con rendering, 12 su conferme/sconfitta remota, 23 su Study/log/attacco/trofei. Corretta anche una callback del bordo Hand su nodi già sostituiti; ultimo test visivo senza errori di script.
Build Web definitiva in `output/web`, rigenerata e verificata: 178 texture Spell, 57 Mage card, 21 hash sorgenti corrispondenti (PASS). Nessuna pubblicazione online.

**Trasferire anche modifiche non committate e file non tracciati.** Nessun commit/push o pubblicazione online effettuato. Un semplice pull non porta questi cambiamenti sull’altro computer. Preservare tutti gli asset aggiunti dall’utente.

---

# Playtest — 28 ottobre 2026, seconda revisione

Ultima richiesta: glitch Study, scelte nel log, attacco con rincorsa/rinculo, pause -10%, blocco Web dopo sconfitta e animazione trofeo.
Dettagli: [docs/PLAYTEST-2026-10-28-B.md](docs/PLAYTEST-2026-10-28-B.md).
80 controlli mirati superati, inclusi 23 con rendering attivo. Il blocco della specifica sessione Web non è stato riprodotto: verificati motore locale e due client simulati tramite snapshot.
Continue/Close chiude la ricevuta locale; conferme danno con limite di 10 secondi dopo l’animazione.
Export Web locale rigenerato e verificato: 178 texture Spell, 57 Mage card, 21 hash corrispondenti. Nessuna pubblicazione online.

---

# Playtest — 28 ottobre 2026

Ultima richiesta: Study Web, conferma carte tenute, bordo senza riempimento, pause animazioni, descrizioni effetti, orientamento cubi, Quest, log e blocco dopo sconfitta.
Dettagli: [docs/PLAYTEST-2026-10-28.md](docs/PLAYTEST-2026-10-28.md).
81 controlli mirati superati. Rigenerato export Web locale; nessuna pubblicazione.
Il danno ora interrompe una mano rimasta aperta: entrambi i client ricevono la conferma, e dopo la sconfitta non viene ripristinata la vecchia board ispezionata.

---

# Playtest — 27 ottobre 2026, seconda revisione

Ultima richiesta: 25 punti su inglese, Bartholomäus, Study, conferme, animazioni, bersagli, log e Nigredo.
Implementazione e limiti: [docs/PLAYTEST-2026-10-27-B.md](docs/PLAYTEST-2026-10-27-B.md).
66 controlli mirati superati. Build Web locale aggiornata, nessuna pubblicazione.
Le conferme danno ora includono tutti gli umani (anche l'attaccante), con il solo Continue locale; Spell/Room hanno timeout di 10 secondi.
Nigredo verificato con snapshot host/client: conversione completata; corretto il messaggio obsoleto dello spettatore, non riprodotto un blocco del motore.

---

# Playtest — 27 ottobre 2026

Ultima richiesta: 11 correzioni UI, animazioni, Log, Vastum e Corrupted Ray.
Implementate e verificate con 39 controlli mirati; dettagli e limiti in [docs/PLAYTEST-2026-10-27.md](docs/PLAYTEST-2026-10-27.md).
Questa sezione supera le indicazioni storiche sul click della carta Avatar: ora apre la carta per consultazione.

---

# Interfaccia e animazioni — 23–24 ottobre 2026 (completate)

Nuova richiesta utente dopo le carte Mago: completare questi 13 punti, anche online.
1. Specializzazione: carte con nomi, domanda evidente e due pulsanti per scegliere.
2. Preparazione: evidenziare il lato come nella playerboard delle spell giocate.
3. Conferma prima di scartare dopo la pesca e prima di scegliere mago/scuola iniziali.
4. Mazzi Quest/Jinx/Upgrade con retro nella Power Board; consultazione alfabetica
   di tutte le definizioni (anche già pescate), titolo Available X; Quest della luna corrente.
5. Carta scuola consultabile come galleria di tutte le spell della scuola.
6. Spell: destro consulta, sinistro lancia; conferma con nome della spell prima del lancio.
7. Animazione danni sulla playerboard anche per i client online.
8. Animazione di piazzamento trap/protection più lenta.
9. Spell lanciata presentata a tutti i giocatori online.
10. Animare piazzamento delle instabilità.
11. Click carta Avatar apre l'Avatar Board.
12. Correggere pausa tra animazione danni Avatar e successivo effetto della spell.
13. Animare il piazzamento delle evocazioni.

Tutti i 13 punti implementati e verificati in Godot 4.7.2.
UI: conferme centralizzate in BetaHUD, destro per ispezione, specializzazioni con
due pulsanti; cornice lato condivisa in TabletopStyle; cataloghi da definizioni
in PowerBoard/ReferenceCardPreview. Avatar card apre la board.
Rete: feedback pubblico dei danni serializzato e deduplicato; le spell online
attendono il click di ogni umano. Piazzamenti world animati nella TabletopShell;
marker più lenti, ricostruzione delle scelte dopo la presentazione dei danni.
Verifiche: nuova suite `ui_online_2026_10_23.gd` 88 controlli passati anche
con rendering OpenGL; `damage_presentation_v2` 15, `avatar_fourth_playtest` 23,
`presentations` 156, `latest_playtest` 14, tutti passati (296 controlli).
Screenshot reali in `docs/handoff-2026-10-18/evidence/ui23-*.png`.
Coperti: scarti confermati, lato Light/Dark, cataloghi completi, click Avatar,
danni letali ricevuti dal client e deduplicati, conferma spell di ogni umano,
conversione dei cubi Avatar subito dopo i danni, piazzamenti locali/remoti.
Export Web definitivo in `output/web`, impostazioni Web 1024/0.68; originali
intatti. PCK 99.589.704 byte, gzip 96.970.470 byte, entrambi sotto 100 MB.
Parità sorgente/export passata: 169 texture Spell disponibili, 57 carte Mago
(incluse le 47 nuove), 13 script interessati identici, cataloghi inizializzati.
Il controllo storico `tools/check_web_export.gd` si ferma sulla PNG personale
`the_eight_spells`, già assente nel sorgente. La suite di parità registra tutte
le 114 Spell senza immagine (incluse scuole future), senza nasconderle né
aggiungerne all'export. Baseline in `evidence/ui24-export-baseline.json`.
Avvio Web e conferme maghi/scuola provati nel browser integrato; nessun errore console.
Dettagli in `docs/UI-ONLINE-2026-10-24.md`. Nessuna pubblicazione o commit.
Non ancora effettuata una partita con amici su PC distinti. Riavviare l'host
con i nuovi script e ricaricare il browser dopo aver aggiornato il Web distribuito.
L'asset utente `assets/evocations/gaea.png` è stato preservato.

# Carte Mago — 23 ottobre 2026 (completate)

Richiesta corrente: produrre le carte PNG dei maghi mancanti, stile `assets/mages`,
statistiche e personaggi dalle Personal Spell nel Codex Arcanum pp. 68–83.
46 maghi senza immagine, più la seconda forma di Hyperion. Nessuna nuova meccanica
o abilitazione dei 31 maghi ancora assenti dal database è parte di questo lavoro.
Fonti estratte dal PDF e prompt/provenienza in `docs/mage-art-2026-10-23/manifest.json`.
47/47 carte verificate e salvate: tutti i 25 maghi nel database hanno ora una PNG.
Elenco, statistiche, prompt e provenienza esatti nel manifest; galleria locale in
`docs/mage-art-2026-10-23/galleria.html`. Import Godot 4.7.2 riuscito senza errori.
Controllo effettivo di `ReferenceCardPreview.card_texture`: 47 nuove texture e 25
maghi del database caricati, zero mancanti. Statistiche delle 15 nuove carte già
nel database coerenti con `mages.json`. Le 10 carte precedenti rimangono intatte.
Immagini incluse nel nuovo export Web. Nessun commit. Non abilitano i 31 maghi
non implementati.

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
