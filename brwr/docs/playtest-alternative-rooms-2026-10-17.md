# Correzioni stanze alternative ed Equipment — 17 ottobre 2026

## Comportamento

- **Bibliotheca of the Order:** Shift-clic sulla spell preparata apre l'ispezione senza selezionarla, scartarla o pagare il costo. Vale per gli slot numerati, Quick e le spell mostrate nella galleria delle scelte. Il clic normale seleziona la carta. La scelta resta sospesa durante l'ispezione e prosegue dopo lo scarto effettivo. La privacy degli slot viene verificata dal percorso di ispezione già esistente.
- **Equipment:** esclusi dai bersagli Model di spell, Quest e scelte condivise, oltre che dal piazzamento delle proprie evocazioni di Eldritch Tentacle. Movimento e piazzamento diretto li rifiutano anche nel motore. Nessun token sulla Loggia; la carta e i danni rimangono sulla PlayerBoard, dove possono essere selezionati per gli effetti consentiti del proprietario. Il riferimento alla posizione del mago rimane nello stato esistente per gli effetti che ne hanno bisogno.
- **Cinder Star:** il JSON controllava erroneamente gli elementi Fire/Profane. Corretto in Combat/Contingency, coerentemente con il testo della carta presente nel progetto. Mass Production completa la Quest sia nella Crypt sia nella Crypt of the Saint. Nessuna modifica alla geometria o al sistema delle stanze: ogni alternativa conserva già l'identità della stanza base attraverso `replaces`.
- **Crusaders' Summoner Room:** entrambi i lati propongono solo evocazioni controllate da avversari entro distanza 1. Danno 2 nella versione distrutta e 10 nella ricostruita; in assenza di bersagli validi la risoluzione termina senza obbligare a scegliere una propria evocazione.

## Implementazione

Nessun nuovo stato di gioco. Le scelte continuano a usare gli indirizzi pubblici e i valori autoritativi esistenti, compatibili con la proiezione di rete. La gestione di Shift viene condivisa tra gli oggetti sulla PlayerBoard e la galleria, leggendo il modificatore prima del callback differito.

File modificati per questi quattro casi: `game.gd`, `beta_hud.gd`, `effect_resolver.gd`, `equipment_rules.gd`, `forgotten_rules.gd`, `school_effects.gd`, `alternative_room_rules.gd`, `data/quests.json`, `data/rooms.json`.

Riferimenti consultati: Codex Arcanum pp. 22 e 24 per Equipment e Mass Production; carta `assets/quests/cinder_star.png`; definizioni e testi delle stanze in `data/rooms.json`.

## Verifiche

- Godot 4.7.2: import e parsing senza errori.
- 10 JSON validi, senza chiavi duplicate; ID e riferimenti `replaces` delle stanze giocabili validi. Room of Rebirth rimane intenzionalmente disabilitata.
- 134 verifiche di gioco: equivalenza delle alternative per le Quest, entrambi i lati di Mass Production, bersagli Equipment, movimento, entrambe le versioni di Crusaders e pagamento di Bibliotheca.
- 25 verifiche UI, sia headless sia con rendering nativo a 1600×900: Shift-clic reale sui due tipi di slot e nella galleria, scarto successivo, privacy, scelta della carta Equipment e dei suoi cubi dalla PlayerBoard. Anteprime renderizzate ispezionate.
- 115 regressioni del playtest precedente superate.
- Build browser locale aggiornata: controllo del pacchetto esportato superato, con le stesse 134 verifiche di gioco e 25 UI eseguite anche sul PCK finale. Sul pacchetto passano inoltre 56 controlli d'integrazione delle scuole, 76 delle regole e 309 della riserva/layout per 2–6 giocatori.

Script diagnostici, screenshot e log in `C:/Users/bigba/AppData/Local/Temp/BRWR_alternative_rooms_20261017/`, fuori dal progetto.

Non eseguito un playtest completo fra due PC su Internet.
