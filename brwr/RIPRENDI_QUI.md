# Ripresa sul laptop — 18 ottobre 2026

Questo è il progetto corrente, comprese le modifiche non committate. L'utente
sincronizzerà l'intera cartella del repository con il laptop Windows. Questi
documenti conservano il contesto della chat, che sul laptop non sarà disponibile.
Non è una release di Possessed completata.

## Checkpoint corrente — lavoro ripreso

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
