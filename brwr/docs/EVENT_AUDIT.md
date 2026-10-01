# Eventi — implementazione e verifica, 1 ottobre 2026

## Risultato

Implementati i 18 eventi senza handler e corretti gli 11 percorsi parziali individuati dall’audit. La suite `event_rules_playtest.gd` copre tutti i 39 ID con 287 controlli superati in Godot 4.7.2. `event_coverage_audit.gd` rimane un ingresso compatibile alla stessa suite. Questo verifica i casi descritti sotto, non tutte le combinazioni possibili di carte.

## Architettura

`draw_event` applica rivelazione/corona/piazzamento. Instant e ingresso degli Always usano `event_sequence`; ciascun effetto usa `event_effect`, e completa il bersaglio corrente prima del successivo. Danni, trigger, scelte e attivazioni continuano a usare lo stack Game esistente. Lo scarto Instant e il suo premio avvengono una sola volta, dopo gli effetti. Le Quest della fase Black Rose aspettano tutti gli eventi, anche entrando dalla Clean-up.

Gli effetti continui dipendono dalle carte presenti in `active_events`. Il filtro di fase impedisce bonus fuori Action. Nessun nuovo database o stato autorevole parallelo. L’ordine della fase resta valido anche se una carta cambia il proprietario della Corona.

## Copertura per carta

| Luna | Eventi | Comportamento verificato |
|---|---|---|
| 1 | Hidden Resources | Premio al Mage piazzato in Cell. |
| 1 | Black Thorns | Due danni a entrambe le evocazioni bersaglio. |
| 1 | Rebirth at Sunset, Rebirth at Noon, Rebirth at Dawn | Solo stanze dei colori richiesti; Throne resta distinta da purple. |
| 1 | Awakening, Midnight Rebirth | Cinque/due cubi nella Black Rose Room. |
| 1 | Gift to Fools | Scuola opzionale per ciascun Mage, prima del successivo e delle Quest. |
| 1 | Dislocation | Collocamento opzionale in qualsiasi stanza, anche partendo dalla Cell. |
| 1 | Puppeteer | Dispatch valido e instabilità su rimozione solo in Action. |
| 1 | A Hard Lesson | Perdita Power e destinazione per Mage; scelta invalida non ripete il costo. |
| 1 | Undead Army | Evocazione opzionale a distanza zero; sostituzione quando i tre slot sono pieni. La sostituzione non emette rimozione/sconfitta. Rispetta le copie indicate nel database. |
| 1 | Black Overload | Un solo cubo BR per piazzamento del Mage. |
| 2 | Abandonment, Battle, Knowledge, Clairvoyance, Growth, Instinct | Premio per colore corretto, solo durante Action e non al dispatch. |
| 2 | Illness | Due cubi per stanza occupata, anche con più Mage; poi tutti nelle Cell. |
| 2 | Vision | Quest della terza luna senza cambiare la luna corrente. |
| 2 | Wave of Fatigue | Scarto della specifica copia scelta; perdita Power solo senza carte. |
| 2 | Revolt of the Servants | Danni dalla Strength delle evocazioni possedute; perdita Power se assenti. |
| 2 | Tribute of the Command | Accetta/rifiuta, danno realmente pagato, scelta e attivazione prima del prossimo Mage. |
| 2 | Renovation | Trofeo trasferito alla BR, instabilità del Mage nella sua stanza. |
| 2 | Reward the Slothful | Completed e Solved distinte. |
| 3 | Only War, Only Peace | Danni una volta dopo l’intero Spell Effect, incluse trap/protection; nessuna ripetizione o effetto fuori fase. |
| 3 | Remembrance | Prima luna poi seconda; attende le scelte degli Instant annidati; scarti singoli. |
| 3 | Assault | Bonus Combat contro Mage ed evocazioni; esclusi danni fisici. |
| 3 | Manipulating the Past | Scarta solo Solved; tre Power persi in assenza. |
| 3 | Pledge | Tre danni a ogni Mage. |
| 3 | Gold to the King | Premio al proprietario della Corona. |
| 3 | Woe | Conversione selezionabile dei cubi, pool aggiornati; danni solo se non convertiti. |
| 3 | Infinite Knowledge | Premio Mage e BR alla risoluzione Quest, senza duplicazione. |
| 3 | Immortals | Cura all’ingresso prima degli altri eventi; immunità anche ai danni reindirizzati/già accodati; fine immunità all’uscita. |
| 3 | False Mercy | Cura solo cubi non-BR, poi danno ai Mage senza cubi BR. |
| 3 | Dominion | Trofeo della sconfitta alla BR. |
| 3 | Power Infusion | Scelta Instant, pagamento completo una volta, pesca Forgotten. |

## Regole e fonti

- Regolamento fornito nel repository, sezioni Corona/ordine, Eventi, Summon Evocations e risoluzione degli effetti. Una Spell Effect comprende le sue frasi: Only War/Peace non si applicano a ogni voce JSON separatamente.
- Screenshot originale Dislocation: Area *; corretto il precedente range 1 nei dati.
- [Errata BRWR Allegato ENG v1.1](https://www.scribd.com/document/834192765/BRWR-Allegato-ENG-v1-1), carta sostitutiva Power Infusion: conferma Instant e rimuove il riferimento all’inizio Action. Corretto il testo JSON; la PNG già presente non è stata rigenerata e può riportare ancora il testo vecchio.
- Woe: la scelta dei cubi della BR è affidata alla Corona, usando il criterio generale del regolamento per le situazioni ambigue. Il testo della carta non nomina esplicitamente chi effettua questa scelta; questa convenzione è esplicitata qui e nel prompt, non presentata come errata ufficiale specifica di Woe.

## Verifiche

- Godot 4.7.2: suite eventi 39/39, 287 controlli; Hand/Targets/Tribute, Reported Rules, Quest Table, Playtest Regressions, Cell Exit, Evocation Phase, Board Actions, Athanor, Azoth Bomb.
- Suite Spell/Event: i controlli Clean-up → A Hard Lesson → fase successiva passano. Restano due fallimenti Soul Transfer già riprodotti sul codice precedente a questo intervento; non sono causati dagli eventi.
- JSON: 39 ID unici, immagini esistenti per tutti gli ID. Diff e parser verificati a fine lavoro.
- Da provare manualmente: interfaccia delle nuove scelte in una partita completa e su due client PvP; incroci fra più eventi e catene di trappole/contingency non esauriti dai test.

## File runtime modificati in questo intervento

- `event_effect_resolver.gd`: sequenza/frame degli eventi, scelte e applicazione degli effetti.
- `game.gd`: pesca da luna esplicita, continuazioni delle fasi, dispatch stack, callback degli eventi, bonus/immunità danni e costo Tribute.
- `effect_resolver.gd`: conserva l’origine Spell del danno alle evocazioni per Assault.
- `quest_manager.gd`: pesca da luna esplicita e premio Infinite Knowledge.
- `data/events.json`: Dislocation, sequenza A Hard Lesson, testo Power Infusion.

Test/documentazione: `event_rules_playtest.gd`, `event_coverage_audit.gd`, `reported_rules_playtest.gd` (fixture Growth in Action), questo documento. Nessun commit.
