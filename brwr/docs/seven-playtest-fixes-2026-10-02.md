# Correzioni playtest — 2 ottobre 2026

Questo intervento conserva le modifiche precedenti non committate.

## Comportamento

- Conversione: instabilità e danni conservano l'ordine. La scelta distingue il cubo preciso anche quando più cubi hanno lo stesso proprietario. L'instabilità cambia colore nello stesso nodo/slot, con restituzione e consumo dei cubi nelle rispettive riserve.
- Indigo Star: la condizione è Combat oppure Contingency dalla Oracle Room, non Aria oppure Acqua. Implementata come elenco di tipi nel dato della quest, senza eccezione per ID nel manager.
- Sconfitta (correzione successiva dell'utente, verificata sul regolamento p.28): le evocazioni evocate restano nella Loggia. Si rimuovono solo quelle assegnate al mago, come le Umbras, una meccanica non ancora implementata. Eliminata la rimozione indiscriminata aggiunta inizialmente; preservati istanze, stanze, danni e numeri delle evocazioni.
- Power Track: centri misurati sulle caselle dell'immagine, con righe leggermente irregolari. Eliminati gli offset fissi per giocatore. Un token solo è centrato; più token sullo stesso punteggio formano un gruppo simmetrico.
- Evocazioni: gli effetti di magie, quest e stanze offrono la sostituzione di una specifica evocazione quando tutti e tre gli slot sono occupati. È possibile rinunciare. La sostituzione non emette eventi di sconfitta/rimozione; il percorso degli eventi già implementava questa distinzione ed è conservato. La primitiva di creazione rimane separata dalla scelta interattiva.
- Summoner Room: problema non riprodotto. Il test attiva realmente la stanza, seleziona una stanza adiacente e verifica 1 danno all'evocazione avversaria. La propria evocazione nella stessa stanza rimane immune. Immortals può impedire il danno; non è stata cambiata questa regola.
- Elementi: verificato che quest ed Enhancement usino il lato attivo delle carte rivelate. L'Enhancement esclude la propria istanza in risoluzione. Nessuna modifica necessaria al conteggio già presente.

## File e funzioni modificati in questo intervento

- `game.gd`: nuovo `summon_evocation_for_effect`; `_prepare_quest_special_choice`, `_prepare_damage_conversion_choices` identificano i cubi per indice oltre che proprietario; `process_damage_resolution` conserva le evocazioni evocate alla sconfitta del mago, come specificato a pagina 28.
- `effect_resolver.gd`: `_summon` usa la scelta condivisa; `convert_damage_cubes` rispetta l'indice selezionato; `_resolve_convert_instability` converte nello slot originale.
- `room.gd`: nuovo `convert_instability_cube` aggiorna stato e colore senza rimuovere/riordinare i nodi.
- `room_effect_resolver.gd`: `_resolve_summon_evocation` usa la scelta condivisa e gestisce la rinuncia.
- `quest_manager.gd`: `_task_matches` supporta `spell_types`.
- `data/quests.json`: condizione e testo di Indigo Star.
- `power_board.gd`: `create_power_track`, `update_player_marker`, `update_black_rose_marker`, `get_marker_offset`; nuovo `_layout_power_markers`.
- `seven_fixes_playtest.gd` e UID: nuova regressione per i casi segnalati, inclusi sostituzione da stanza/Fountain e rinuncia.
- `evocation_quest_rules_playtest.gd`: aspettativa aggiornata per la sconfitta del mago.
- `power_board_playtest.gd`: verifica centratura singola e del gruppo, griglia e overflow.

## Verifiche eseguite

Godot 4.7.2, esecuzione headless:

- `seven_fixes_playtest.gd`: PASS.
- `evocation_quest_rules_playtest.gd`: PASS.
- `power_board_playtest.gd`: PASS.
- `object_choices_playtest.gd`: PASS.
- `table_repair_playtest.gd`: PASS.
- `evocation_token_playtest.gd`: PASS.
- `event_rules_playtest.gd`: 39/39 eventi, 287 controlli, zero errori.

Import/editor headless senza errori di parser; JSON validato anche per chiavi duplicate; diff e whitespace controllati. Rendering Power Board con GL Compatibility ispezionato in `output/power-board/preview.png`.

Restano da verificare manualmente una partita PvP completa, la comodità dei click nei gruppi di token e la sequenza specifica del playtest in cui Summoner Room non ha inflitto danno. Nessun commit effettuato.
