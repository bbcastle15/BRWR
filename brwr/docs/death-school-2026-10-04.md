# Death e Mors — 4 ottobre 2026

Implementate le 12 magie Death (36 copie nella Libreria), i Grimori iniziali
Oblivion e The End, Mors e la sua magia personale Consuming Soul. Tutti i 26 lati
hanno dati, effetti e immagini utilizzabili nel gioco.

## Fonti e correzioni grafiche

- `../materials/Codex Arcanum.pdf`, pagine 13–15 e 79: regole Death, carte e Mors.
- Regolamento base, pagine 18 e 28: risoluzione delle frasi e sconfitta del Mago.
- Legende di elementi, tipi di magia e bersagli fornite dall'utente.
- Conferma esplicita dell'utente: Dark Omens ha **Profane su entrambi i lati**.

Il Codex aggiornato fa risolvere Destiny al passo 3 della sconfitta del Mago e
assegna un Trofeo aggiuntivo per la sconfitta automatica causata da Destiny.
Il prototipo fotografato della scuola descriveva invece una vecchia risoluzione
in Cleanup: per dati, immagine e motore è stata usata la regola del Codex.

Corretti Mage/Model, Self, Profane, Sacred, Magic, Trap, il titolo Bone Shield e
il simbolo Permanent. Annihilation usa Magic (cerchio con scintille). I PNG delle
magie sono 1024 × 1536, con entrambi i lati leggibili nello stesso orientamento.

Le immagini sono state generate/corrette con il tool **imagegen integrato**.
Prompt, riferimenti, passaggi di correzione e destinazioni sono registrati in
`docs/death-art-work.json`. Gli originali generati sono conservati nella
directory indicata nel manifest; il gioco legge esclusivamente gli asset copiati
nel repository.

## Stato e flusso

1. Setup carica Mors e i due Grimori dal database esistente. La carta scuola
   Death compare nelle normali scelte della scuola e della pesca.
2. Preparation, proprietà delle singole carte, slot fisici e privacy usano le
   strutture già esistenti. Le magie non creano una seconda rappresentazione
   autoritativa della plancia.
3. `MageState.destiny_tokens` conserva un ID del proprietario per ogni token,
   massimo tre complessivi per Mago. Assegnare un token riserva un cubo reale.
   Il PlayerBoard mostra token e cubo colorato, anche agli altri giocatori.
4. Il resolver Death aggiunge operazioni alla pila di risoluzione esistente:
   assegnazione, costi in Trofei, alternative, bersagli multipli, protezioni e
   attivazioni temporaneamente controllate. Il proprietario delle evocazioni
   non cambia quando un altro Mago ne controlla un'attivazione.
5. Alla sconfitta, i proprietari scelgono in ordine di gioco quanti Destiny
   risolvere. Le conversioni precedono il conteggio dei contributi per i punti;
   i token risolti restituiscono i cubi, quelli conservati restano assegnati.
   La sconfitta automatica con tre Destiny assegna anche il Trofeo aggiuntivo.
6. Trappole e protezioni entrano nel normale sistema di trigger. Dark Omens
   Dark resta permanente e guadagna Potere solo al verificarsi del trigger.
   Cleanup e rimozione delle carte riutilizzano il ciclo esistente. Le evocazioni
   possedute sopravvivono alla sconfitta del Mago.

Per Annihilation Dark il danno e la conversione appartengono alla stessa frase:
conversione, reazioni successive e sconfitta rispettano questo ordine. Le frasi
che colpiscono più Maghi applicano il danno a tutti prima delle sconfitte.

## File e funzioni interessati da questo intervento

Le modifiche preesistenti a playmat, schede della mano, animazioni e trasporto
Render erano già nel working tree e sono state conservate. La lista seguente
identifica il lavoro Death, non attribuisce a questo intervento tutto il diff.

| File | Modifiche |
| --- | --- |
| `data/spells.json` | 12 definizioni Death e Consuming Soul; elementi, bersagli, trigger, costi e frasi. |
| `data/mages.json` | Mors: HP 11, mano 7, forza 2, velocità 2, limite Quest 2, Consuming Soul. |
| `data/school_specializations_v19.json` | Oblivion e The End. |
| `mage_state.gd` | Campo autoritativo `destiny_tokens`. |
| `death_effect_resolver.gd` | Nuovo resolver senza stato proprio: `prepare`, `resolve`, `process_destiny`, `process_mages`, `apply_trigger_target`, `announce_spell`; helper per contesti/accodamento e `queue_sentence`, `defer_damage_post_event`, `finish_sentence`, `process_sentence`. |
| `effect_resolver.gd` | `resolve_effect` delega i nuovi tipi; `_damage_mage`, `_resolve_convert_damage`, `_resolve_convert_damage_each_other_mage` rispettano l'immunità; `convert_damage_cubes` conserva ordine e disponibilità dei cubi. |
| `game.gd` | `load_school_specializations`; `deal_damage`, `deal_damage_from_evocation`; `place_mage_in_cell`, `place_instability`; `_prepare_damage_conversion_choices`, `_prepare_spell_secondary_effect_choice`; `process_resolution_stack`, `process_damage_resolution`, `process_effect_sequence_resolution`, `process_trigger_spell_resolution`, `process_evocation_activation_resolution`; `_beta_player_state`, `_perform_evocation_physical_attack`. |
| `triggered_spell_manager.gd` | `trigger_matches`: trigger Death e tempi di protezione/reazione. |
| `quest_manager.gd` | `_complete_quest`: evento pubblico `quest_completed` per Final Judgment. |
| `player_board.gd` | `refresh` e nuovo `refresh_destiny_tokens`: token con cubi dei proprietari. |
| `network_projection.gd` | `apply`: ripristino dei Destiny dalla proiezione pubblica dell'host. |
| `online_session.gd` | `_ready`: include nuovi resolver e database nell'impronta di compatibilità. |
| `death_school_playtest.gd` | Nuova copertura funzionale di 26 lati e casi limite. |
| `death_ui_network_playtest.gd` | Caricamento immagini, rendering plancia/scuola, serializzazione, privacy e autorizzazione delle scelte. |
| `five_fixes_playtest.gd` | `solve` e chiamanti: attendono l'animazione Quest già esistente prima di verificarne gli effetti. |
| `docs/death-art-work.json` | Manifest grafico. |
| `docs/death-school-2026-10-04.md` | Questo rapporto. |

Asset finali, con i corrispondenti file Godot `.import`:

```text
assets/spells/tearing.png
assets/spells/entropy.png
assets/spells/bone_shield.png
assets/spells/lugubrious_toll.png
assets/spells/lethal_touch.png
assets/spells/dark_omens.png
assets/spells/annihilation.png
assets/spells/final_judgment.png
assets/spells/sacrificial_pyre.png
assets/spells/despair.png
assets/spells/martyrdom.png
assets/spells/repentance.png
assets/spells/consuming_soul.png
assets/schools/death.png
assets/mages/mors.png
assets/tokens/destiny.png
assets/tokens/permanent.png
```

Godot ha inoltre generato gli UID per i nuovi script. Il pacchetto Web locale è
stato ricostruito in `output/web`; nessun commit, push o deployment.

## Verifiche eseguite

- Godot **4.7.2**: import completo da editor headless, senza errori del parser.
- Tutti i JSON di `data/` analizzati; 42 ID magia univoci; riferimenti di Mors e
  Grimori validi; 36 copie Death; 13 PNG magia presenti a 1024 × 1536.
- `death_school_playtest.gd`: **229 controlli, 26 lati, zero fallimenti**.
  Comprende costo e limite dei Destiny, conservazione dei cubi e del loro ordine,
  scelte di proprietari differenti, copie duplicate, salute massima per Tearing,
  immunità a magie singole/area/globali, esclusione Forgotten, costi facoltativi,
  conversioni prima delle sconfitte e controllo temporaneo delle evocazioni.
- `death_ui_network_playtest.gd`: **40 controlli, zero fallimenti**, sia nel
  progetto sia caricando il pacchetto esportato. Destiny pubblico, informazioni
  private filtrate e rifiuto delle scelte inviate dal giocatore sbagliato.
- Rendering Godot reale acquisito e controllato: `output/death-school/mors-board.png`
  e `output/death-school/death-school-choice.png`.
- `event_rules_playtest.gd`: **39/39 eventi, 287 controlli, zero fallimenti**.
- Passano anche `playtest_regressions`, `spell_instability_playtest`,
  `evocation_quest_rules_playtest`, `room_damage_playtest`, `seven_fixes_playtest`,
  `athanor_enhancement_playtest`, `evocation_phase_playtest`, `cell_exit_playtest`,
  `reported_rules_playtest`, `quest_table_playtest`, `spell_event_playtest`,
  `five_fixes_playtest`, `school_ui_playtest`, `tabletop_shell_playtest`,
  `tabletop_presentation_network_playtest`, `screen_layout_playtest`.
- Esportazione Web completata; `tools/check_web_export.gd`: **PASS** sul pacchetto.
- Diff completo ispezionato; controllo whitespace con `git diff --check`.

I log sono in `output/death-school/`. Un test preesistente stampa ancora
`Unknown Damage resolution step: redirect_applied` nel ramo di redirezione del
danno verso un'evocazione; il test passa. Il ramo era già presente in HEAD e non
è stato modificato nel lavoro Death. Non è un errore di parsing; rimane una
diagnostica da approfondire separatamente.

## Verifiche manuali ancora necessarie

- Partita completa con Death insieme ad Agony/Alchemy, in particolare finestre
  con più trappole/protezioni e Destiny di proprietari diversi.
- Playtest tra due PC/browser attraverso il relay reale: qui sono stati
  verificati serializzazione, privacy e pacchetto, non una sessione Internet.
- Leggibilità e selezione delle carte nelle risoluzioni schermo usate dai
  giocatori; i controlli visivi di questo intervento sono a 1600 × 1000.

Il pacchetto Web contiene immagini di alta qualità e supera il limite ordinario
di 100 MB per un file GitHub (PCK circa 695 MiB): il build locale riesce, ma la
pubblicazione deve usare il sistema di distribuzione previsto dal progetto.
