extends RefCounted

const CONFIG_PATH := "res://online_server_url.txt"
const WS_PATH := "/ws"

static func configured_web_base() -> String:
	# Browser clients are served by the same Render service as the relay.
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("window.location.origin", true)).strip_edges()
		var normalized := _normalize_http_base(origin)
		if not normalized.is_empty():
			return normalized

	var from_env := OS.get_environment("BRWR_ONLINE_BASE").strip_edges()
	if not from_env.is_empty():
		var normalized_env := _normalize_http_base(from_env)
		if not normalized_env.is_empty():
			return normalized_env

	if FileAccess.file_exists(CONFIG_PATH):
		var configured := FileAccess.get_file_as_string(CONFIG_PATH).strip_edges()
		if not configured.is_empty() and not configured.contains("YOUR-RENDER-SERVICE"):
			return _normalize_http_base(configured)

	return ""

static func create(code: String) -> String:
	var base := configured_web_base()
	if base.is_empty() or code.strip_edges().is_empty():
		return ""
	return base + "/#code=" + code.strip_edges().uri_encode()

static func parse(link: String) -> Dictionary:
	var value := link.strip_edges()
	if value.is_empty() or not value.contains("#"):
		return {}

	var base := _normalize_http_base(value.get_slice("#", 0))
	if base.is_empty():
		return {}

	var params := {}
	for part in value.get_slice("#", 1).split("&"):
		if part.contains("="):
			params[part.get_slice("=", 0)] = part.get_slice("=", 1).uri_decode()

	var code := str(params.get("code", "")).strip_edges()
	if code.is_empty() or code.length() > 128:
		return {}

	return {
		"address": websocket_address(base),
		"code": code,
	}

static func websocket_address(address: String = "") -> String:
	var value := address.strip_edges()
	if value.is_empty():
		value = configured_web_base()
		if value.is_empty():
			return ""

	if value.begins_with("ws://") or value.begins_with("wss://"):
		return _normalize_ws(value)

	var base := _normalize_http_base(value)
	if base.is_empty():
		return ""

	var scheme := "wss://" if base.begins_with("https://") else "ws://"
	var authority := base.substr(base.find("://") + 3)
	return scheme + authority + WS_PATH

static func _normalize_http_base(value: String) -> String:
	var base := value.strip_edges().trim_suffix("/")
	if base.is_empty():
		return ""

	if base.begins_with("ws://"):
		base = "http://" + base.trim_prefix("ws://")
	elif base.begins_with("wss://"):
		base = "https://" + base.trim_prefix("wss://")
	elif not base.begins_with("http://") and not base.begins_with("https://"):
		base = "https://" + base

	# Render/public deployment uses a bare origin. Keep localhost + optional port
	# valid as well so the relay can be tested locally.
	var pattern := RegEx.new()
	pattern.compile("^https?://(\\[[0-9a-fA-F:]+\\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?$")
	var matched := pattern.search(base)
	if matched == null:
		return ""

	var port := matched.get_string(2).trim_prefix(":")
	if not port.is_empty() and (int(port) < 1 or int(port) > 65535):
		return ""

	return base

static func _normalize_ws(value: String) -> String:
	var ws := value.strip_edges().trim_suffix("/")
	var as_http := ws.replace("wss://", "https://").replace("ws://", "http://")

	# Accept either an origin or an explicit /ws endpoint.
	if as_http.ends_with(WS_PATH):
		as_http = as_http.trim_suffix(WS_PATH)
		ws = ws.trim_suffix(WS_PATH)

	if _normalize_http_base(as_http).is_empty():
		return ""

	return ws + WS_PATH
