# Stanze e regolamenti — 21 ottobre 2026

## Correzione applicata

La precedente estensione per colore era errata. La selezione standard ora usa esclusivamente gli abbinamenti espliciti `replaces`. Crypt of the Saint sostituisce Crypt, mai Cemetery. Il filtro vale per menu, selezioni salvate, scelta casuale e proiezione online. Una selezione non valida nel setup ricade sulla stanza base.

Le quattro stanze Gaea (Emerald Rose, Thorny Clearing, Life Fountain, Indoor Forest) sono escluse: appartengono allo scenario, che non è implementato. Conserviamo i rispettivi abbinamenti come metadati per lo sviluppo futuro. Anche Apocalypse e Room of Rebirth restano escluse.

Conferma documentale: Duel Lex p.21, Duel Void p.21 e Duel Kami p.27 prescrivono stanze omonime ignorando il qualificatore in corsivo. Non autorizzano sostituzioni arbitrarie per colore. Per Rebirth si applicano inoltre le regole di compatibilità già presenti.

Fonti: [catalogo ufficiale Duel](https://app.ludusmagnusstudio.com/pages/_BRW-DUEL/brw-duelRules.php), [regolamenti Rebirth](https://app.ludusmagnusstudio.com/pages/_BRWR/brwrRules.php).

## Abbinamenti nel database

| Variante | Sostituisce | Setup standard |
|---|---|---|
| Black Rose Room - Apocalypse | Black Rose Room | Esclusa |
| Deep Black Rose Room | Black Rose Room | Sì |
| Emerald Rose | Black Rose Room | Esclusa |
| Occult Black Rose Room | Black Rose Room | Sì |
| Crypt of the Saint | Crypt | Sì |
| Room of Rebirth | Modalità dedicata | Esclusa |
| Sacrificial Altar of Madness | Sacrificial Altar | Sì |
| Whales Cemetery | Cemetery | Sì |
| Crusaders' Summoner Room | Summoner Room | Sì |
| Lost Alchemical Laboratory | Alchemical Laboratory | Sì |
| Ludus Arena | Arena | Sì |
| Abyssal Observatory | Observatory | Sì |
| Bibliotheca of the Order | Bibliotheca | Sì |
| Sanctuary of Anubis | Sanctuary | Sì |
| Forge of the Void | Forge | Sì |
| Indoor Forest | Treasure Room | Esclusa |
| Life Fountain | Garden | Esclusa |
| Templars' Treasure Room | Treasure Room | Sì |
| Thorny Clearing | Forge | Esclusa |
| Zen Garden | Garden | Sì |
| Abyss of Faith | The Abyss | Sì |
| Abyss of Hel | The Abyss | Sì |
| Blasphemous Oracle Room | Oracle Room | Sì |
| Ancient Pleasures Room | Pleasures Room | Sì |
| Skulls' Throne Room | Throne Room | Sì |
| Templars' Armory | Armory | Sì |

## Raccolta documentale

I 20 PDF già presenti in `materials/` coprono il nucleo Rebirth, FAQ, compatibilità, Skirmish, Magister, Apocalypse, Dread Forge, Deadly Mask, Gaea, Irene, Jukas, Seal of Fire e i sei fascicoli Rotas. I nomi abbreviati (antiques, last, once, silk...) non significavano regolamenti mancanti. Presenti anche Codex BRW e Codex Arcanum Rebirth.

I nuovi PDF sono in `materials/official_missing/`; `sources.json` registra URL, dimensioni e SHA-256. Sono conservati senza sovrascrivere i tuoi originali. I `.txt` sono estrazioni per ricerca, non sostituiscono le pagine illustrate.

- BRW: base, Inferno, Crono, Hidden Thorns, Sator, Familiars; schede Asymmetric Mages raccolte separatamente.
- Duel: Lex, Void, Kami. Le sezioni di compatibilità sono le fonti più dirette per le relative stanze.
- Nova Aetas Renaissance: base, Stretch Goals, Under Siege, Vesuvio, Hyperion, Minotaur, Mediceo, Draco, Catacombs. Sono documentazione del gioco d'origine: il materiale BRWR del crossover Magister è nel `magister.pdf` già presente. Non equivale all'implementazione di tutte queste espansioni in BRWR. Vesuvio nel catalogo è v0.94, non da trattare come regolamento definitivo.
- Dungeonology: Rocca e regole BRW Familiars. Rocca documenta il crossover Pets; la compatibilità non trasferisce automaticamente tutte le regole Dungeonology a BRWR.
- Requiem: scaricato il regolamento base; verificato il catalogo ufficiale e cercato il materiale Magician/crossover. Il regolamento base da solo non basta per implementare Totentanz, Mors o il nuovo Avatar. Non sono stati inventati dati delle carte mancanti.

Cataloghi ufficiali: [BRW](https://ludusmagnusstudio.com/black-rose-wars/black-rose-wars-rules/), [NAR](https://app.ludusmagnusstudio.com/pages/_NAR/narRules.php), [Requiem](https://app.ludusmagnusstudio.com/pages/_RQM/rqmRules.php), [Dungeonology crossover](https://app.ludusmagnusstudio.com/pages/_DNG/dngCrossovers.php).

## Verifiche

- Godot 4.7.2 `room_families.gd`: 3306 controlli, zero errori. Tutte le coppie base/variante, selezioni obsolete, random e divieto Gaea.
- `alternative_rooms.gd`: 122 controlli, zero errori sugli effetti.
- Nessuna nuova espansione abilitata soltanto perché è stato scaricato il suo regolamento.

## File acquisiti e fonti dirette

| File | Download ufficiale | Stato |
|---|---|---|
| BRW_Core_ENG.pdf | [PDF](https://ludusmagnusstudio.com/download/116233/) | 40 pagine, verificato |
| BRW_Inferno_ENG.pdf | [PDF](https://ludusmagnusstudio.com/download/117569/) | 20 pagine, verificato |
| BRW_Crono_ENG.pdf | [PDF](https://ludusmagnusstudio.com/download/117968/) | 12 pagine, verificato |
| BRW_Hidden_Thorns_ENG.pdf | [PDF](https://ludusmagnusstudio.com/download/117975/) | 4 pagine, verificato |
| Duel_Lex_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1XAZFsQqqLBLSVP_25N645Npq305XZTcT) | 24 pagine, verificato |
| Duel_Void_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1ac5cJkqjmGA69AwF9JgBMQm6g6xseKTr) | 24 pagine, verificato |
| Duel_Kami_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1TRmcp81Y_VOUCvkERejFNkVj8anEH8od) | 28 pagine, verificato |
| BRW_Sator_ENG.pdf | [PDF](https://ludusmagnusstudio.com/download/117608/) | 24 pagine, verificato |
| BRW_Familiars_Multi.pdf | [PDF](https://ludusmagnusstudio.com/download/117595/) | 24 pagine, verificato |
| NAR_Core_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1_5nVCBPSnODmvhOjETpln-lcts5E6PUh) | 64 pagine, verificato |
| NAR_Under_Siege_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1zjgDbDyuLGW3OwHWTL6W9--5Rgku3wQr) | 16 pagine, verificato |
| NAR_Vesuvio_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1XoLjGef0UXXfHX4d3p8CFcVnKh8VEIKz) | 16 pagine, verificato |
| NAR_Stretch_Goal_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1gesYjWibTVlyAiLHWA0xc2vGK7MlTNfh) | 40 pagine, verificato |
| NAR_Hyperion_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1kaTO61mQq08WKl0eUqR9M9iPCMtL83Bi) | 16 pagine, verificato |
| NAR_Minotaur_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1oXZ-d5IRjQhj83rb00Zw2Do1M5fAZYRG) | 8 pagine, verificato |
| NAR_Mediceo_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=152UZML9dmmM6AWgMvKFsUi_vbmlEozu5) | 16 pagine, verificato |
| NAR_Draco_Rulebook_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1wXunGlqpvRRKKpjA7C7U6X51pfFZc6W4) | 12 pagine, verificato |
| NAR_Catacombs_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1-v3F5AXxEAn8meeKeNV-FuUahOUxBfWG) | 32 pagine, verificato |
| Dungeonology_Rocca_ENG.pdf | [PDF](https://www.ludusmagnusstudio.com/resources_web/dungeonology/DNG_ROCCA_Rulebook_ENG_compressed.pdf) | 40 pagine, verificato |
| Requiem_Core_ENG.pdf | [PDF](https://drive.google.com/uc?export=download&id=1cc1mhT1eShlaNdUobDzZFlZRUkItWnuB) | 48 pagine, verificato |
| BRW_Asymmetric_Mages.pdf | [PDF](https://ludusmagnusstudio.com/download/117630/) | 6 pagine, verificato |

Il catalogo Requiem Print & Play consultato elenca l’allegato Ashes 12; non è stato trovato lì un regolamento Magician completo. Il collegamento Asymmetric Mages del riquadro generale sul sito punta erroneamente a Familiars: è stato usato il collegamento del titolo specifico (117630).
