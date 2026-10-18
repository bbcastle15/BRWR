extends Node

const WEB_PORT := 8080
const SOCKET_PORT := 27847
const DESCRIPTION_PREFIX := "BRWR"

var _upnp: UPNP = null
var _gateway: UPNPDevice = null
var _mapped_ports: Array[int] = []
var external_address := ""
var last_message := ""

func open_brwr_ports() -> Dictionary:
	if OS.has_feature("web"):
		return _result(false, "", "UPnP non disponibile nel client Web.")

	close_brwr_ports()

	_upnp = UPNP.new()
	var discover_result := _upnp.discover(4000, 2, "InternetGatewayDevice")
	print(
		"BRWR UPnP discovery result=%d devices=%d"
		% [discover_result, _upnp.get_device_count()]
	)

	if discover_result != UPNP.UPNP_RESULT_SUCCESS or _upnp.get_device_count() == 0:
		return _result(
			false,
			"",
			"UPnP: router non trovato. La sala resta disponibile solo in LAN."
		)

	_gateway = _upnp.get_gateway()

	# FASTGate can advertise an InternetGatewayDevice while miniupnpc/Godot marks
	# it DISCONNECTED. If so, try the low-level UPNPDevice control methods anyway.
	if _gateway == null or not _gateway.is_valid_gateway():
		_gateway = _find_force_candidate()

	if _gateway == null:
		return _result(
			false,
			"",
			"UPnP: dispositivo trovato ma nessun endpoint IGD utilizzabile. "
			+ "La sala resta disponibile solo in LAN."
		)

	print(
		"BRWR UPnP candidate[%d]: valid=%s status=%d service=%s description=%s igd_service=%s control=%s our_addr=%s"
		% [
			str(_gateway.is_valid_gateway()),
			_gateway.igd_status,
			_gateway.service_type,
			_gateway.igd_service_type,
			_gateway.igd_control_url,
			_gateway.igd_our_addr
		]
	)

	external_address = _gateway.query_external_address().strip_edges()
	print("BRWR UPnP external address before mapping: " + external_address)

	for port in [WEB_PORT, SOCKET_PORT]:
		# Ignore delete failure: the mapping may simply not exist yet.
		var delete_result := _gateway.delete_port_mapping(port, "TCP")
		print("BRWR UPnP delete TCP %d -> %d" % [port, delete_result])

		var mapping_result := _gateway.add_port_mapping(
			port,
			port,
			"%s TCP %d" % [DESCRIPTION_PREFIX, port],
			"TCP",
			0
		)
		print("BRWR UPnP add TCP %d -> %d" % [port, mapping_result])

		if mapping_result != UPNP.UPNP_RESULT_SUCCESS:
			_remove_created_mappings()
			return _result(
				false,
				external_address,
				"UPnP: FASTGate rilevato (status DISCONNECTED), ma apertura TCP %d rifiutata: codice %d. "
				% [port, mapping_result]
				+ "Serve accesso al port mapping del router oppure IPv4 pubblico configurabile."
			)

		_mapped_ports.append(port)

	if external_address.is_empty():
		external_address = _gateway.query_external_address().strip_edges()

	if external_address.is_empty():
		return _result(
			true,
			"",
			"UPnP: TCP 8080 e 27847 aperte forzando il FASTGate, ma non è stato restituito l'IP WAN."
		)

	if _is_private_or_cgnat_ipv4(external_address):
		return _result(
			true,
			external_address,
			"UPnP: porte aperte, ma WAN IP %s è privato/CGNAT; l'accesso Internet diretto può non funzionare."
			% external_address
		)

	return _result(
		true,
		external_address,
		"UPnP OK (fallback FASTGate) · TCP 8080 e 27847 aperte · IP pubblico router: %s"
		% external_address
	)

func _find_force_candidate() -> UPNPDevice:
	for i in range(_upnp.get_device_count()):
		var d := _upnp.get_device(i)
		if d == null:
			continue

		print(
			"BRWR UPnP candidate[%d]: valid=%s status=%d service=%s description=%s igd_service=%s control=%s our_addr=%s"
			% [
			i,
			str(d.is_valid_gateway()),
			d.igd_status,
			d.service_type,
			d.description_url,
			d.igd_service_type,
			d.igd_control_url,
			d.igd_our_addr
		]
		)

		# Preferred fallback: exactly the case observed on FASTGate.
		if (
			d.igd_status == UPNPDevice.IGD_STATUS_DISCONNECTED
			and not d.igd_control_url.is_empty()
			and not d.igd_service_type.is_empty()
		):
			print("BRWR UPnP: forcing DISCONNECTED IGD candidate %d" % i)
			return d

	# Last resort: a device with a parsed IGD control endpoint.
	for i in range(_upnp.get_device_count()):
		var d := _upnp.get_device(i)
		if d != null and not d.igd_control_url.is_empty() and not d.igd_service_type.is_empty():
			print("BRWR UPnP: forcing non-standard IGD candidate %d" % i)
			return d

	return null

func close_brwr_ports() -> void:
	_remove_created_mappings()
	_gateway = null
	_upnp = null
	external_address = ""

func _remove_created_mappings() -> void:
	if _gateway != null:
		for port in _mapped_ports.duplicate():
			var result := _gateway.delete_port_mapping(port, "TCP")
			print("BRWR UPnP cleanup TCP %d -> %d" % [port, result])
	_mapped_ports.clear()

func _exit_tree() -> void:
	close_brwr_ports()

func _result(ok: bool, address: String, message: String) -> Dictionary:
	last_message = message
	return {
		"ok": ok,
		"external_address": address,
		"message": message
	}

func _is_private_or_cgnat_ipv4(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false

	var a := int(parts[0])
	var b := int(parts[1])

	if a == 10 or a == 127:
		return true
	if a == 192 and b == 168:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	if a == 100 and b >= 64 and b <= 127:
		return true
	return false
