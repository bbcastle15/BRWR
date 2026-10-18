# Playtest Forge, Jinx e Anubis — 16 ottobre 2026

## Correzioni e verifiche

| Punto | Risultato |
| --- | --- |
| 1. Bewitching Garments | La scelta esclude Equipment, Pestis, Nightmare e modelli che non possono ricevere Upgrade. L'Upgrade assegnato compare sulla carta dell'evocazione nella PlayerBoard; un clic apre la carta e indica il destinatario. |
| 2. Pupa con Grafted Crossbow | Command avvia direttamente la sequenza interattiva dell'evocazione, senza la precedente pianificazione duplicata. Consuma un solo token fisico. Contro un mago la balestra sostituisce l'attacco con il furto di 1 Power. |
| 3. Sesta scuola | Selezionare, annullare o cancellare pescate conserva la posizione dello scorrimento della Libreria. |
| 4. Rotten | Carta a effetto unico: nessuna scelta Light/Dark, nessuna indicazione di lato nella preparazione e nessuna evidenziatura di mezza carta quando rivelata. Le due rappresentazioni precedenti continuano a risolvere lo stesso effetto. |
| 5. Talos's Intervention | Verificato il danno ad area su due evocazioni: la Protection annulla il danno solo a quella che l'ha attivata, assegna Hyperdermis a quella stessa evocazione e viene consumata. L'altra subisce normalmente il danno. |
| 6. Rimuovere una propria evocazione | È consentito dalle regole. Non viene più selezionata automaticamente l'unica evocazione disponibile. Per un bersaglio Evocation senza vincoli incompatibili è disponibile il Dummy Target; non rimuove un modello e non paga un costo. Le frasi successive della Quest continuano normalmente. |
| 7. Forgotten nello Studio | Lo scarto facoltativo viene accettato anche per una Forgotten senza scuola attiva. La carta viene rimossa dal gioco, come previsto, anche nello Studio parallelo online. |
| 8. Mass Production | Verificato che la scelta comprenda solo le proprie Pupa, comprese quelle appena evocate. Il testo della richiesta specifica destinatario e provenienza del danno. |
| 9 e 12. Anubis evocazione | La Jinx viene assegnata al bersaglio sopravvissuto ed è visibile nella plancia e nella scheda Jinx. Se l'attacco ha già rimandato il mago in cella, quel mago ignora l'effetto successivo. Il log identifica la Jinx assegnata. I danni delle abilità mantengono l'evocazione come fonte. |
| 10. Scheda Jinx | Terza scheda accanto a Cards e Quests, con carte grandi, scorrimento orizzontale, cubi di progresso, conteggio e ispezione al clic. Le bozze di preparazione/pesca si conservano cambiando scheda. |
| 11. Pegasus's Feathers | La richiesta riporta il nome e l'effetto: piazzare 1 Instability nella stanza dell'evocazione. Scelte Use / Skip; verificata l'applicazione alla fine dell'attivazione. |
| 13. Anubis mago | Aggiunti dati del mago e tre copie della Personal Spell Eternal Curse. Entrambi i lati implementati. Il lato Dark evoca Pharaoh nella stanza dove il bersaglio è stato sconfitto. Se Anubis è scelto come mago, Wrath of the Jackal God viene esclusa dal mazzo Forgotten, anche quando il mazzo viene ricreato. |
| 14. Personal Spell | Verificate tutte le 18 Librerie: nessuna include Personal o Forgotten. Le Personal scartate durante lo Studio non entrano negli scarti della scuola. |

Corretto inoltre il caso Vulnerability: il suo danno opzionale si applica se era già assegnata prima della nuova Jinx, non quando viene assegnata Vulnerability stessa.

## Regole consultate

- Regolamento Rebirth inglese v1.2: Studio, evocazioni, Dummy Target, danni e sconfitta; in particolare pp. 14, 20–21, 26–28.
- Codex Arcanum: Rotten p. 21; Forge pp. 22–25; Forgotten p. 60; Anubis mago/Eternal Curse p. 70; Anubis evocazione p. 103; Upgrade p. 108; Jinx p. 109.
- [FAQ ufficiali Ludus Magnus Studio](https://app.ludusmagnusstudio.com/pages/_BRWR/brwrFaq.php), versione inglese v1.2 del 5 febbraio 2026: Personal Spell, rimozione delle proprie evocazioni, immunità del mago in cella e Vulnerability.

## Implementazione

Lo stato rimane nelle classi esistenti: `MageState.jinxes`, `EvocationState.upgrades`, carte e mazzi del motore. HandOverlay e PlayerBoard leggono questi dati; la proiezione di rete già esistente li trasmette senza duplicare lo stato. La privacy delle spell preparate resta invariata.

File interessati: `game.gd`, `effect_resolver.gd`, `forgotten_attachments.gd`, `forgotten_rules.gd`, `school_effects.gd`, `beta_hud.gd`, `hand_overlay.gd`, `player_board.gd`, `spell_card_state.gd`, `spell_card_preview.gd`, `tabletop_shell.gd`, `data/spells.json`, `data/mages.json`, `data/attachments.json`.

## Token illustrati

Completato il primo gruppo Nigredo, Succubus e Cadaver: ritratto circolare, bordo del proprietario, numero della copia, nome/HP al passaggio del mouse e nomi facoltativi. La scelta dei bersagli usa gli stessi token. Nelle stanze affollate i token si dispongono nella fascia centrale e si riducono senza coprire pergamena o cubi. Le altre evocazioni conservano il segnalino precedente.

Asset e logica: `assets/tokens/evocations/`, `assets/tokens/evocation_portrait.gdshader`, `evocation_token.gd`, `game.gd`, `tabletop_shell.gd`. Prompt di generazione in `docs/evocation-token-art-2026-10-16.json`.

## Verifiche

Eseguiti con Godot 4.7.2:

- Import dell'editor e controllo di parsing senza errori.
- Validazione dei 10 JSON, 267 ID spell unici e riferimenti Personal/Forgotten dei 9 maghi.
- 115 regressioni dei casi di gioco con richieste di scelta e risoluzione effettive, senza errori.
- 31 verifiche UI con clic reali nel viewport: Upgrade, Jinx, privacy, preparazione, sesta scuola e proiezione di rete. Rendering nativo ispezionato a 1600×900.
- 55 verifiche dei token, incluse selezione, movimento animato, finestre modali, sincronizzazione e sei evocazioni nella stessa stanza.
- Suite precedenti: 56 verifiche d'integrazione delle scuole e 76 verifiche delle regole, senza errori.
- Build Web esportata e verificata, inclusi 309 controlli della riserva e del layout. Avvio nel browser, scelta di Anubis e rimozione di Wrath of the Jackal God verificati nel log, senza errori della console.

Gli script diagnostici e i log sono nelle cartelle temporanee della sessione, fuori dal progetto. Anteprime in `output/previews/`.

Non eseguito un playtest completo fra due PC su Internet.
