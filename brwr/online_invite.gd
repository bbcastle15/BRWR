extends RefCounted

const HTTP_PORT := 8080
const SOCKET_PORT := 27847

static func web_base(address: String) -> String:
	var value := address.strip_edges().trim_suffix("/")
	if not value.contains("://"):
		value = "http://" + value + ("" if value.contains(":") else ":%d" % HTTP_PORT)
	var pattern := RegEx.new()
	pattern.compile("^https?://(\\[[0-9a-fA-F:]+\\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?$")
	var matched := pattern.search(value)
	if matched == null: return ""
	var port := matched.get_string(2).trim_prefix(":")
	if not port.is_empty() and (int(port) < 1 or int(port) > 65535): return ""
	return value

static func create(address: String, code: String) -> String:
	var base := web_base(address)
	if base.is_empty() or code.is_empty(): return ""
	return base + "/#code=" + code.uri_encode() + "&port=%d" % SOCKET_PORT

static func parse(link: String) -> Dictionary:
	var base := web_base(link.get_slice("#", 0))
	if base.is_empty() or not link.contains("#"): return {}
	var params := {}
	for part in link.get_slice("#", 1).split("&"):
		params[part.get_slice("=", 0)] = part.get_slice("=", 1).uri_decode()
	var code := str(params.get("code", ""))
	var port := int(params.get("port", SOCKET_PORT))
	if code.is_empty() or code.length() > 128 or port < 1 or port > 65535: return {}
	var authority := _authority(base)
	var host := authority.get_slice("]", 0) + "]" if authority.begins_with("[") else authority.get_slice(":", 0)
	return {"address": ("wss://" if base.begins_with("https://") else "ws://") + host + ":%d" % port, "code": code}

static func websocket_address(address: String) -> String:
	var value := address.strip_edges()
	if value.begins_with("ws://") or value.begins_with("wss://"):
		var as_http := value.replace("wss://", "https://").replace("ws://", "http://")
		return value if not web_base(as_http).is_empty() else ""
	var base := web_base(value)
	if base.is_empty(): return ""
	var authority := _authority(base)
	var host := authority.get_slice("]", 0) + "]" if authority.begins_with("[") else authority.get_slice(":", 0)
	return ("wss://" if base.begins_with("https://") else "ws://") + host + ":%d" % SOCKET_PORT

static func _authority(url: String) -> String:
	return url.substr(url.find("://") + 3)
