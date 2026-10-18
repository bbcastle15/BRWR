# BRWR FASTGate UPnP fallback

Sostituisce solo `upnp_manager.gd`.

Il FASTGate viene rilevato come `InternetGatewayDevice:1`, ma Godot/miniupnpc
lo marca `IGD_STATUS_DISCONNECTED`. Questa patch tenta comunque i metodi
low-level `UPNPDevice.add_port_mapping()` sul dispositivo rilevato.

Dopo la sostituzione:

1. chiudi BRWR;
2. rilancia `Ospita-Online.cmd`;
3. premi `Crea sala PvP`;
4. manda sia il messaggio mostrato nella UI sia le righe del terminale che
   iniziano con `BRWR UPnP`.

Se il mapping riesce, il link verrà aggiornato automaticamente con l'IP WAN
restituito dal router.
