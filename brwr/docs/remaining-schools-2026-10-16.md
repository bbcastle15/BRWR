# Scuole del Codex e riserve del tavolo

## Contenuti implementati

Completate, nell'ordine del Codex: **Forge, Heka, Hex, Lex, Nightmare,
Oracle, Pestilence, Shamanic, Technomancy, Void e War**.

- 132 spell di scuola, entrambi i lati, copie e due grimori iniziali per scuola.
- Etna e la spell personale Master Craftsman.
- 13 nuove definizioni di Evocations/Equipments; riutilizzate le definizioni
  già presenti di Pharaoh, Templarii, Aruspice, Umbra, Colossus e Dagon.
- Il database contiene ora 18 scuole con 12 spell regolari ciascuna,
  266 definizioni di spell complessive e 55 Evocations.
- Nessuna immagine generata o sostituita. Le definizioni di spell ed Evocations
  precedenti a questo intervento non sono state modificate.

Fonti: `materials/Codex Arcanum.pdf`, pp. 22–25, 29–59, 72 e 112;
regolamento Rebirth per equipaggiamenti, bersagli, sconfitta e Cleanup.

## Regole e integrazione

`school_effects.gd` estende il risolutore con effetti condivisi e selezioni
che sospendono/riprendono la sequenza esistente. `equipment_rules.gd`,
`oracle_rules.gd` e `pestilence_rules.gd` gestiscono rispettivamente gli
Equipments, Prophecy/Revelation e Infectio/Pestis. Lo stato resta nelle classi
PlayerState, MageState, EvocationState e ActiveSpellState già utilizzate.

Sono inclusi azioni e modificatori degli Equipments, assegnazione/scelta di
Upgrades e Jinxes, Nightmares assegnati, Totems, spese di Quest/Eventi,
attivazioni ripetute, sostituzione della spell in risoluzione e nuovi trigger.
Le scelte conservano il flusso esistente di bersagli e la privacy delle carte.
La proiezione di rete trasferisce Infectio, cubi riservati e dati necessari
alle nuove evocazioni; il controllo versione online include i nuovi moduli.

## Scuole disponibili nelle nuove partite

Una scuola entra nella selezione casuale soltanto se:

- `rules_implemented` è vero;
- sono presenti 12 spell regolari con entrambi i lati;
- i due grimori iniziali hanno sei spell valide ciascuno;
- esistono le immagini della scuola e delle 12 spell;
- esistono definizioni e immagini delle evocazioni e degli Upgrades/Jinxes
  direttamente richiesti dagli effetti.

Attualmente risultano complete **Agony, Alchemy, Death, Chaos, Geomancy,
Druidic, Famine e Forge**. La partita seleziona sei scuole da questo gruppo.
Le altre dieci restano implementate nei JSON e nel motore, ma escluse dalla
selezione finché mancano le immagini. Aggiungendo gli asset nei percorsi
consueti saranno riconosciute al prossimo avvio/esportazione, senza una
seconda lista manuale di scuole abilitate.

Gli alias del caricatore preservano i nomi dei file forniti:
`firos_bow`, `taloss_corset`, `cerebreal_implant`, `crafted_crossbow`, `locust`.

## Tavolo

Le 24 Evocations non Forgotten sono disposte in quattro colonne a sinistra
dell'Event Board. Restano cliccabili per consultare la carta e le copie
disponibili. A destra della Power Board sono mostrate esclusivamente le
scuole attive e i loro scarti. Il display si aggiorna anche quando un client
riceve le scuole della partita dall'host.

La geometria della Loggia e delle due board resta quella già calibrata.
A 1600×900 lo zoom iniziale misurato è 0,569 per 2/4 giocatori,
0,543 per 3 e 0,519 per 5/6; la riserva occupa 748×732 unità del tavolo,
invece dell'intera colonna verticale di 24 carte.

## Verifiche eseguite

Godot 4.7.2, JSON validi, ID/riferimenti e confronto dei dati preesistenti:

| Verifica | Risultato |
|---|---:|
| Entrambi i lati delle nuove spell | 853 controlli, 0 errori |
| Rami alternativi | 822 controlli, 0 errori |
| Regole specifiche delle nuove scuole | 76 controlli, 0 errori |
| Integrazione di effetti, UI e proiezione di rete nel pacchetto finale | 56 controlli, 0 errori |
| Regressione Famine | 311 controlli, 0 errori |
| Regressione Druidic | 191 controlli, 0 errori |
| Regressione Forgotten | 318 controlli, 0 errori |
| Stanze alternative | 0 errori |
| Riserve, disponibilità scuole e layout da 2 a 6 giocatori | 309 controlli, 0 errori |
| Render dei layout a 2 e 6 giocatori | 132 controlli, 0 errori; PNG ispezionate |

Gli script e i log diagnostici restano in
`%TEMP%/BRWR_remaining_schools_20261015`, senza aggiungere test temporanei al
progetto. L'esportazione browser è in `output/web`; il pacchetto viene
ricontrollato con Godot per risorse, regole, integrazione e riserve.

Resta da effettuare un playtest umano completo, inclusa una partita PvP tra
PC diversi. I test sulla proiezione di rete non sostituiscono quel playtest.
