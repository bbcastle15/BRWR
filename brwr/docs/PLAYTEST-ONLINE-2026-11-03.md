# Playtest online — 3 novembre 2026

Intervento sulla lista di 19 segnalazioni. Modifiche locali applicate; controlli
di sorgente, pacchetto Web e integrità del bundle superati.

## Comportamento aggiornato

| Punti | Modifica |
| --- | --- |
| 1 | Mescolata e sei rivelazioni più lente; le Scuole restano visibili fino a **Continue**. Saltare l'animazione rivela le carte, senza confermare automaticamente. |
| 2–3 | Rimosso il pulsante flottante **Show cards** quando la mano è chiusa. I sei pulsanti laterali hanno dimensioni uguali. |
| 4 | Momentum mostra **Stay in this Room** fuori dalla Cell. Dalla Cell deve ancora uscire. |
| 5 | Il ghost del danno sopravvive ai refresh della plancia. Lo stato finale asincrono viene sincronizzato anche senza una nuova scelta. Una plancia appena aperta dal nuovo giocatore non viene richiusa dal cambio viewer. |
| 6 | Click sul proprio token Mage apre le azioni fisiche quando disponibili; i token degli altri non ricevono questa scorciatoia. |
| 7 | Nuovi retro Jinx e Upgrade in alta risoluzione negli slot della PowerBoard. |
| 8 | Banner a ogni nuova Activation, comprese quelle consecutive dello stesso giocatore e dell'Avatar. Rimossa la pausa fissa aggiuntiva prima del primo Comando Avatar. |
| 9–10 | Nome utente richiesto prima di entrare. Il nome viaggia nella lobby e nello stato autorevole; banner, messaggi e titoli lo riutilizzano. Mage e School separati da un diamante. |
| 11 | Il cambio turno lascia chiusa la PlayerBoard; si apre dal banner, dal token o quando una scelta richiede la plancia. |
| 12, 14 | Waiting descrive l'operazione: Upgrade, Jinx, Evocation, conversione, ecc. I nomi interni dei resolver non diventano messaggi; le scelte private restano private. Rimossi anche i messaggi del relay rimasti in italiano. |
| 13 | Destiny più grande, con piazzamento animato sulla plancia Mage o Avatar. |
| 15 | 49 fronti Quest con glifi originali del regolamento. Originali preservati; nuove versioni in `assets/quests/symbols`. |
| 16 | Ogni Evocation remota mantiene l'identità dell'istanza autorevole, indipendentemente dallo slot. Cadaver resta visibile e cliccabile dopo il movimento nella stanza di un'altra Evocation. |
| 17–18 | Aggiornamento finale anche per l'ultima Instability e i Damage dell'Avatar; il refresh non dipende più dall'arrivo di un altro input. |
| 19 | La Hand usa il resolver grafico condiviso: Natural Invocation carica il fallback Personal già presente. |

## Scelte tecniche

- `OnlineSession` pubblica le proiezioni cambiate ogni 250 ms e ai punti di
  sincronizzazione esistenti. Invii identici vengono deduplicati per peer;
  viene sempre rispettato il filtro delle informazioni private.
- `NetworkProjection` conserva le istanze remote delle Evocations tramite
  l'identificatore autorevole. Le callback di ispezione continuano a riferirsi
  al modello vivo dopo lo spostamento.
- Danni e Destiny sono animazioni dello stato, non copie indipendenti delle
  regole. Il ghost del danno usa la plancia stabile come parent.
- `tools/build_quest_faces.py` compone testo e glifi dal database corrente.
  Nessun effetto Quest è stato modificato per questa richiesta. Template,
  manifest e note sono in `assets/quests/production`; i fronti precedenti
  restano al loro posto.
- I PNG originali restano ad alta risoluzione; la compressione Web agisce
  esclusivamente sulla copia temporanea di esportazione.

File principali: `game.gd`, `online_session.gd`, `network_projection.gd`,
`tabletop_shell.gd`, `beta_hud.gd`, `main_menu.gd`, `mage_token.gd`,
`player_board.gd`, `avatar_board.gd`, `death_effect_resolver.gd`,
`school_draw_presentation.gd`, `hand_overlay.gd`, `power_board.gd`,
`reference_card_preview.gd`, `relay/server.js` e nuovi asset.

## Verifiche eseguite

462 asserzioni distinte passate:

| Check in `docs/handoff-2026-10-18/checks` | Asserzioni | Copertura |
| --- | ---: | --- |
| `nov03_online_playtest.gd` | 21 | Proiezioni, codec reale, deduplica, nomi, Cadaver, ultima Instability, Damage Avatar, Cell, Momentum, fallback grafico e privacy Waiting. |
| `nov03_online_animation.gd` | 18 | Host/client con animazioni attive: refresh durante danno letale, fine overlay, nuovo turno dalla Cell, Explore remoto effettivo e click reale sul Cadaver spostato da entrambi i punti di vista. |
| `nov03_school_draw.gd` | 36 | Intro, Continue, skip, input, resize, client e assenza di consumo RNG. Eseguito con rendering OpenGL. |
| `nov03_playtest_ui.gd` | 72 | Nome obbligatorio, scambio profili lobby, sei giocatori a 720p, pulsanti, Quest, retro, Destiny Mage/Avatar, banner e click reale sul token Mage. OpenGL. |
| `avatar_rules.gd` | 135 | Regressione regole Avatar. |
| `oct29_avatar_reactions.gd` | 99 | Regressione reazioni Avatar. |
| `oct28c_remote_avatar.gd` | 8 | Regressione presentazioni Avatar sul client. |
| `nov01_playtest.gd` | 73 | Regressione UI, Cell, privacy, reazioni, movimenti e rimozioni. Aspettativa aggiornata alla nuova richiesta di non aprire automaticamente la plancia. |

Import/parser Godot eseguito senza errori; `git diff --check` pulito,
16 documenti JSON validati, hash dei 49 fronti Quest verificati e
`node --check relay/server.js` passato. Screenshot e manifest ImageGen nella
cartella `docs/handoff-2026-10-18/evidence/`, con prefissi `nov03-playtest-`
e `nov03-school-draw-`.

## Versione browser

Aggiornati `output/web` e `deploy/web_bundle`. Parità passata per 239 Spell
texture, 57 Mage Card, 49 Quest, 49 hash di codice/dati e versione del protocollo.
Verificati anche i nuovi retro Jinx/Upgrade. Passato `tools/check_web_export.gd`,
lo stesso controllo usato dal launcher host. Compressione Web 1024 / 0.67.

- PCK: 107.944.532 byte; gzip: 105.099.563 byte.
- Cinque parti per ciascuno dei due file, massimo 24 MiB per parte.
- Hash SHA-256 delle concatenazioni uguali ai due file esportati.
- Baseline: `evidence/nov03-playtest-export-baseline.json`.
- Manifest bundle: `evidence/nov03-playtest-web-bundle.json`.
- Riepilogo controlli: `evidence/nov03-playtest-checks.json`.

Il bundle locale è pronto per la pubblicazione, che non è stata eseguita.
I browser collegati alla versione pubblica non riceveranno questi cambiamenti
finché non sarà pubblicato il bundle aggiornato. Non eseguire automaticamente
`tools/publish_render.ps1`: include commit e push.

## Limiti della verifica

I test online usano due istanze Game nella stessa esecuzione Godot, il codec
e il protocollo effettivi, con un trasporto di test. Non sono una partita
completa fra due PC attraverso Internet e un browser. L'esatto blocco della
partita originale non è stato riprodotto; sono state corrette e verificate
le fragilità individuate nei percorsi coinvolti. Il log WASAPI non prova una
causa del blocco: altri log con lo stesso errore audio proseguivano la partita.

Nessun commit, push o deploy pubblico. Non riabilitare Hyperion/Myrmidones né
sovrascrivere le PNG Hex originali con le anteprime ancora da approvare.
