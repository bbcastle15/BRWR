# BRWR UPnP diagnostic patch

Sostituisce solo `upnp_manager.gd`.

Novità:
- prova prima discovery IGD standard;
- se nessun gateway valido, ripete la discovery senza filtro;
- stampa nel terminale tutti i dispositivi UPnP trovati e i relativi campi IGD;
- mostra nella UI un riepilogo diagnostico;
- se il fallback trova un gateway valido, tenta automaticamente le porte TCP 8080 e 27847.

Uso:
1. copia `upnp_manager.gd` nella root `brwr` sovrascrivendo quello attuale;
2. chiudi e riapri `Ospita-Online.cmd`;
3. premi `Crea sala PvP`;
4. copia l'output del terminale che inizia con `BRWR UPnP`.
