# Browser online e cinque segnalazioni — 3 ottobre 2026

## Avvio

Eseguire `Ospita-Online.cmd`. L'host usa il pacchetto appena esportato; gli amici
aprono il link della sala nel browser e premono **Entra nella partita**.
La guida completa è in `DEVELOPMENT_AND_ONLINE.md`.

La sala usa WebSocket TCP 27847. Il server HTTP integrato distribuisce il gioco
su TCP 8080. Non servono VPN, servizi di relay o programmi sul PC degli amici.
Per Internet occorrono IPv4 pubblico raggiungibile, port mapping e firewall
configurati sull'host. Queste impostazioni non sono state modificate.

Game e i risolutori esistenti rimangono autorevoli sull'host. I client ricevono
la proiezione filtrata per il proprio giocatore; non eseguono le decisioni
di gioco. Codice casuale della sala, controllo versione, posto del giocatore
e revisione della richiesta vengono verificati prima di accettare gli input.

## File e funzioni cambiati per l'online

| File | Funzioni / modifica |
| --- | --- |
| `online_session.gd` | `_ready`, `_process`, `_make_peer`, `host`, `join`, `_peer_connected`, `_connected`, `_authenticate`, `_update_lobby`, `_lobby`, `can_start`, `start_match`, `_rejected`, `_begin`, `_create_game`, `_ready_for_state`, `publish`, `_snapshot`, `submit_local`, `_choose`, `_connection_failed`, `_peer_left`, `_match_paused`, `_disconnected`, `return_to_menu`. Sostituzione ENet con WebSocket, sala esplicita, autenticazione, aggiornamenti filtrati e sospensione alla disconnessione. |
| `main_menu.gd` | `_ready`, `_label`, `_count`, `_solo`, `_web_directory`, `_host`, `_refresh_invite`, `_join`, `_refresh_lobby`, `_reset`. Creazione sala, link, elenco partecipanti, avvio host e ingresso browser. |
| `network_projection.gd` | `build`, `apply`: trofei, scarti Quest e identità stabile delle Quest tra snapshot. |
| `beta_hud.gd` | `_build_ui`: nel browser il comando di uscita torna al menu e chiude la connessione. |
| `online_invite.gd` (nuovo) | `web_base`, `create`, `parse`, `websocket_address`, `_authority`: validazione e lettura degli inviti. |
| `web_host.gd` (nuovo) | `start`, `_process`, `_prepare_response`, `_headers`, `_error`, `_send_chunk`, `_close`, `stop`, `_exit_tree`: server HTTP limitato ai file della build, trasmissione non bloccante, gzip e limiti alle richieste. |
| `project.godot` | Renderer Web Compatibility. |
| `export_presets.cfg` (nuovo) | Export Web senza thread, dati e immagini inclusi; esclusione di strumenti, test e output. |
| `tools/host_web.ps1` (nuovo) | Verifica Godot/template 4.7.2, impronta del working tree, export, gzip, verifica PCK e avvio dello stesso PCK come host. |
| `tools/check_web_export.gd` (nuovo) | `_initialize`, `_process`, `run`: caricamento scene, dati, anteprime e immagini dal solo PCK esportato. |
| `Ospita-Online.cmd` (nuovo) | Avvio del launcher PowerShell. |
| `.gitignore` | Esclusione dei metadati generati `web_build.json`. |
| `DEVELOPMENT_AND_ONLINE.md` | Istruzioni host/amici, Fastweb, aggiornamenti e laptop; sostituzione delle precedenti istruzioni UDP. |

`online_playtest.gd` aggiorna `run` e `_process` per sala WebSocket e posti
dinamici. `web_online_playtest.gd` aggiunge verifiche degli inviti, risposte
HTTP e proiezione privata/pubblica. I nuovi script hanno i rispettivi `.gd.uid`.

## Segnalazioni di gioco

1. **Albify Dark:** la conversione veniva correttamente richiesta, ma un refresh
   della plancia distruggeva i cubi con i pulsanti di selezione. Ora i nodi dei
   cubi occupati vengono riutilizzati. Riprodotto il passaggio da quattro
   bersagli cliccabili a zero dopo tre frame; dopo la correzione restano quattro.
   La conversione cambia il proprietario negli indici selezionati senza riordino.
2. **Warrior Wizard:** nessuna modifica alla regola. La carta richiede Health
   non superiore a 3; Health è il valore della carta, non la vita rimasta dopo
   i danni (regolamento Rebirth, pagina 21). Nigredo ha Health 4 ed è escluso
   anche a 1/4. Verificati rimozione di un Cadaver valido, bersaglio indipendente
   dell'Instabilità e assegnazione della ricompensa.
3. **Earth Tempest:** recupero e progressione contano soltanto l'Elemento nel
   lato attivo. I simboli stampati come requisito dell'Enhancement non sono
   Elementi della carta. Liquid Fire Dark (Fire) viene rifiutata sia nelle
   opzioni sia dal risolutore. Conservato il simbolo All come jolly.
4. **Soul Transfer Light:** un `target_room_id` presente ma vuoto saltava la
   scelta. Ora vengono validate le stanze e richiesta la selezione esplicita;
   due Costrutti in stanze diverse offrono entrambe le stanze. Il bersaglio
   dell'effetto della stanza viene poi scelto separatamente, dalla stanza
   attivata. Un bersaglio precompilato illegale non consuma la magia.
   La carta consente un Costrutto di qualsiasi proprietario.
5. **Illusory Moon:** il piazzamento diretto aggiorna subito anche i segnalini
   dei modelli. Verificato il flusso completo con spostamento di entrambi i maghi.

| File | Funzioni cambiate per queste cinque segnalazioni |
| --- | --- |
| `player_board.gd` | `refresh_damage_track` |
| `game.gd` | `_quest_side_has_any_element`, `_prepare_spell_secondary_effect_choice`, `process_spell_cast_resolution` |
| `effect_resolver.gd` | `_side_has_any_element`, `_place_mage_direct`; eliminato `_side_element_symbols`, rimasto senza utilizzatori |
| `quest_manager.gd` | `_count_matching_element_symbols` |
| `five_fixes_playtest.gd` (nuovo) | Riproduzioni e regressioni dei cinque casi, inclusi pulsanti cubi e conferma UI differiti. |
| `online_rules_check.gd` | `run`, nuovo `choose_conversion`: attende e risponde alle scelte effettive della conversione prima delle asserzioni. |
| `spell_event_playtest.gd` | `run`: fixture deterministica e correzione dell'aspettativa obsoleta che escludeva Costrutti avversari da Soul Transfer. |

Non sono stati modificati i JSON per questi cinque casi. Le precedenti
modifiche a plance, grafica, Quest, selezione di oggetti e relativi test presenti
nel working tree sono state conservate; non sono nuove modifiche di questa
sessione. Il diff complessivo è stato ispezionato. Nessun commit o push.

## Verifiche eseguite

- Godot 4.7.2 reale, esportazione Web e controllo del pacchetto PCK: PASS,
  senza errori di parser/GDScript. Tutte le 29 immagini Spell caricate dal PCK.
- `five_fixes_playtest.gd`: PASS.
- `online_rules_check.gd`, `spell_event_playtest.gd`: PASS.
- `quest_table_playtest.gd`, `evocation_quest_rules_playtest.gd`,
  `hand_targets_playtest.gd`, `seven_fixes_playtest.gd`: PASS.
- `web_online_playtest.gd`: PASS (inviti, IPv6, URL invalidi, HTTP GET/HEAD,
  404/405, percorsi non autorizzati, MIME/cache, privacy e identità Quest).
- `online_playtest.gd`, due processi reali su loopback: PASS host e client,
  setup → Study → Preparation → prime azioni, privacy, input altrui e obsoleti.
- Prova separata di autenticazione: rifiutati codice/versione errati;
  ingresso corretto accettato, posto liberato dopo disconnessione dalla sala.
- Prova manuale nel browser Chromium integrato, collegato al PCK host su
  loopback: link precompilato → ingresso → scelta mago/scuola/grimorio →
  Dislocation con clic sulla stanza → Study con scelta delle immagini →
  Preparation I/II/III/Quick → mano nascosta e conferma → lancio di Marbling
  dalla plancia → ispezione ingrandita della carta rivelata. Nessun errore o
  warning nella console del browser durante questa prova. Non è una verifica
  con Chrome su un secondo computer.
- Sintassi di tutti i nove file JSON in `data`: PASS.
- `git diff --check`: PASS (avvisi CRLF/LF, nessun errore di whitespace).

I log e le fixture diagnostiche temporanee sono in `output`, esclusa da Git.

## Limiti e verifica manuale restante

- Il menu PvP offre attualmente due giocatori: il database contiene solo due
  maghi e due scuole. La sala supporta 2–6 posti, ma questo non rende complete
  partite con contenuti aggiuntivi non ancora presenti.
- Una partita completa da due PC diversi, tramite la linea Fastweb, resta da
  verificare. I test locali non dimostrano la raggiungibilità da Internet.
- Il server è HTTP/WS senza cifratura TLS. Non sono implementati salvataggio
  o riconnessione; una disconnessione sospende la partita.
- Download corrente: circa 463 MB complessivi compressi. Ogni avvio del
  launcher esporta le modifiche correnti; gli amici ricaricano il nuovo link.
  Nessun aggiornamento durante una partita.
- Verificare nel playtest reale la leggibilità a diverse risoluzioni, i cinque
  casi riportati e una partita fino al conteggio finale. I test automatici non
  sostituiscono questa prova completa.
