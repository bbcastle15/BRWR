extends RefCounted

const CERT_ENV := "BRWR_TLS_CERT"
const KEY_ENV := "BRWR_TLS_KEY"

static func load_server_options() -> Dictionary:
	var cert_path := _resolve_path(OS.get_environment(CERT_ENV).strip_edges())
	var key_path := _resolve_path(OS.get_environment(KEY_ENV).strip_edges())

	if cert_path.is_empty() or key_path.is_empty():
		return {
			"ok": false,
			"message": "TLS non configurato. Avvia tools/setup_tls.ps1 e poi Ospita-Online.cmd."
		}
	if not FileAccess.file_exists(cert_path):
		return {"ok": false, "message": "Certificato TLS non trovato: " + cert_path}
	if not FileAccess.file_exists(key_path):
		return {"ok": false, "message": "Chiave TLS non trovata: " + key_path}

	var certificate := X509Certificate.new()
	var error := certificate.load(cert_path)
	if error != OK:
		return {
			"ok": false,
			"message": "Impossibile caricare il certificato TLS: %s (%s)" % [cert_path, error_string(error)]
		}

	var key := CryptoKey.new()
	error = key.load(key_path)
	if error != OK:
		return {
			"ok": false,
			"message": "Impossibile caricare la chiave TLS: %s (%s)" % [key_path, error_string(error)]
		}

	return {
		"ok": true,
		"options": TLSOptions.server(key, certificate),
		"certificate": certificate,
		"key": key,
		"cert_path": cert_path,
		"key_path": key_path
	}

static func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
