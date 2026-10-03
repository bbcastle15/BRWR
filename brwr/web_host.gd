extends Node

# Serves only the browser build. Never exposes the repository, directories,
# save data or files supplied by a request path. Rules/RPC use OnlineSession.
const PORT := 8080
const MAX_CLIENTS := 24
const CHUNK_SIZE := 65536
const MIME := {
	"html": "text/html; charset=utf-8", "js": "application/javascript",
	"wasm": "application/wasm", "pck": "application/octet-stream",
	"png": "image/png", "svg": "image/svg+xml", "ico": "image/x-icon"
}
var server := TCPServer.new()
var clients: Array[Dictionary] = []
var files: Dictionary = {}

func start(directory: String, port: int = PORT, bind_address: String = "*") -> Error:
	if OS.has_feature("web"): return ERR_UNAVAILABLE
	for required in ["index.html", "index.js", "index.wasm", "index.pck"]:
		if not FileAccess.file_exists(directory.path_join(required)):
			return ERR_FILE_NOT_FOUND
	files.clear()
	for filename in DirAccess.get_files_at(directory):
		if (filename.begins_with("index.") or filename == "favicon.png") and MIME.has(filename.get_extension()):
			files["/" + filename] = directory.path_join(filename)
	files["/"] = files["/index.html"]
	return server.listen(port, bind_address)

func _process(_delta: float) -> void:
	while server.is_connection_available():
		var peer := server.take_connection()
		if clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		clients.append({"peer": peer, "request": PackedByteArray(), "pending": PackedByteArray(), "file": null, "responding": false, "sent": 0, "time": Time.get_ticks_msec()})
	for client in clients.duplicate():
		var peer: StreamPeerTCP = client.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(client.time) > 30000:
			_close(client)
			continue
		if not client.responding:
			var available := peer.get_available_bytes()
			if available == 0: continue
			if available + client.request.size() > 8192:
				_error(client, "431 Request Header Fields Too Large")
				continue
			var result := peer.get_partial_data(available)
			if result[0] != OK:
				_close(client)
				continue
			client.request.append_array(result[1])
			if client.request.get_string_from_utf8().contains("\r\n\r\n"):
				_prepare_response(client)
		if client.responding:
			_send_chunk(client)

func _prepare_response(client: Dictionary) -> void:
	var request: String = client.request.get_string_from_utf8()
	var first := request.get_slice("\r\n", 0).split(" ")
	if first.size() != 3:
		_error(client, "400 Bad Request")
		return
	if first[0] not in ["GET", "HEAD"]:
		_error(client, "405 Method Not Allowed")
		return
	# Exact allowlist lookup: no decoding/concatenation of user-controlled paths.
	var route := first[1].get_slice("?", 0)
	if not files.has(route):
		_error(client, "404 Not Found")
		return
	var path: String = files[route]
	var encoding := ""
	for header in request.split("\r\n"):
		if header.to_lower().begins_with("accept-encoding:") and header.to_lower().contains("gzip") and FileAccess.file_exists(path + ".gz"):
			encoding = "Content-Encoding: gzip\r\n"
	var file := FileAccess.open(path + (".gz" if not encoding.is_empty() else ""), FileAccess.READ)
	if file == null:
		_error(client, "503 Service Unavailable")
		return
	client.pending = _headers("200 OK", int(file.get_length()), MIME[path.get_extension()], encoding).to_utf8_buffer()
	client.responding = true
	if first[0] == "GET": client.file = file
	else: file.close()

func _headers(status: String, length: int, content_type: String, extra: String = "") -> String:
	return "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nVary: Accept-Encoding\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n%s\r\n" % [status, content_type, length, extra]

func _error(client: Dictionary, status: String) -> void:
	client.responding = true
	client.pending = _headers(status, 0, "text/plain").to_utf8_buffer()

func _send_chunk(client: Dictionary) -> void:
	if client.pending.is_empty() and client.file != null:
		if client.file.get_position() < client.file.get_length():
			client.pending = client.file.get_buffer(CHUNK_SIZE)
		else:
			client.file.close()
			client.file = null
	if client.pending.is_empty():
		_close(client)
		return
	var result: Array = client.peer.put_partial_data(client.pending)
	if result[0] != OK:
		_close(client)
		return
	if int(result[1]) > 0:
		client.pending = client.pending.slice(int(result[1]))
		client.time = Time.get_ticks_msec()

func _close(client: Dictionary) -> void:
	client.peer.disconnect_from_host()
	if client.file != null: client.file.close()
	clients.erase(client)

func stop() -> void:
	server.stop()
	for client in clients.duplicate(): _close(client)

func _exit_tree() -> void:
	stop()
