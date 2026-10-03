extends SceneTree

const Invite = preload("res://online_invite.gd")
const BoardProjection = preload("res://network_projection.gd")
var elapsed := 0.0

func _initialize() -> void:
	call_deferred("run")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 30:
		push_error("WEB ONLINE PLAYTEST TIMEOUT")
		quit(1)
	return false

func run() -> void:
	var invitation := Invite.create("203.0.113.5", "a&b#c")
	assert(invitation == "http://203.0.113.5:8080/#code=a%26b%23c&port=27847")
	assert(Invite.parse(invitation) == {"address": "ws://203.0.113.5:27847", "code": "a&b#c"})
	assert(Invite.parse("https://play.example.org/#code=abc").address == "wss://play.example.org:27847")
	assert(Invite.parse("http://[2001:db8::1]:8080/#code=abc").address == "ws://[2001:db8::1]:27847")
	for bad in ["file:///secret", "javascript:alert(1)", "http://user:secret@example.org", "http://example.org/../secret", "http://example.org:99999", "http://example.org\r\nBad: x"]:
		assert(Invite.web_base(bad).is_empty(), bad)
	assert(Invite.parse("http://localhost:8080/#code=abc&port=0").is_empty())
	var fixture := "res://output/web-test-fixture"
	DirAccess.make_dir_recursive_absolute(fixture)
	for name in ["index.html", "index.js", "index.wasm", "index.pck"]:
		var file := FileAccess.open(fixture.path_join(name), FileAccess.WRITE)
		file.store_string("fixture:" + name)
		file.close()
	var server = preload("res://web_host.gd").new()
	root.add_child(server)
	assert(server.start(ProjectSettings.globalize_path(fixture), 18080, "127.0.0.1") == OK)
	var response: Array = await request("/")
	assert(response[1] == 200 and response[3].get_string_from_utf8() == "fixture:index.html")
	assert(response[2].has("Cache-Control: no-store"))
	response = await request("/index.wasm", HTTPClient.METHOD_HEAD)
	assert(response[1] == 200 and response[3].is_empty())
	assert(response[2].has("Content-Type: application/wasm"))
	for path in ["/game.gd", "/.git/config", "/%2e%2e/game.gd", "/index.html/secret"]:
		response = await request(path)
		assert(response[1] == 404, path)
	response = await request("/", HTTPClient.METHOD_POST)
	assert(response[1] == 405)
	server.stop()
	server.queue_free()
	await _projection_check()
	print("WEB ONLINE PLAYTEST PASS: invitations, HTTP allowlist/HEAD/MIME/cache, private projections, public board state")
	quit()

func request(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET) -> Array:
	var http := HTTPRequest.new()
	root.add_child(http)
	assert(http.request("http://127.0.0.1:18080" + path, [], method) == OK)
	var result: Array = await http.request_completed
	http.queue_free()
	return result

func _projection_check() -> void:
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	for i in range(8): await process_frame
	game.players[0].hand.append(game.spell_database.get_spell("albify"))
	game.players[1].hand.append(game.spell_database.get_spell("soul_transfer"))
	game.players[0].trophies.assign([1])
	game.black_rose_trophies.assign([0, 1])
	game.quest_discard.append(game.quest_database.get_quest("shattered_illusion"))
	var quest := QuestState.new(game.quest_database.get_quest("warrior_wizard"), 1)
	quest.progress = 1
	game.players[1].active_quests.append(quest)
	game.players[0].active_quests.append(QuestState.new(game.quest_database.get_quest("guarding_wisdom"), 0))
	var state: Dictionary = BoardProjection.build(game, 1)
	assert(not state.players[0].has("hand"))
	assert(not state.players[0].active_quests[0].has("id"))
	assert(state.players[1].hand[0].id == "soul_transfer")
	var replica = load("res://game.tscn").instantiate()
	replica.network_client = true
	replica.local_viewer_index = 1
	replica.enable_beta_hud = false
	replica.auto_start_game_flow = false
	root.add_child(replica)
	for i in range(8): await process_frame
	BoardProjection.apply(replica, state)
	assert(replica.players[0].hand == [null])
	assert(replica.players[0].trophies == [1])
	assert(replica.black_rose_trophies == [0, 1])
	assert(replica.quest_discard[0].id == "shattered_illusion")
	var same_quest = replica.players[1].active_quests[0]
	quest.progress = 2
	quest.revealed = true
	BoardProjection.apply(replica, BoardProjection.build(game, 1))
	assert(replica.players[1].active_quests[0] == same_quest, "Inspection must retain the same quest instance across snapshots")
	assert(same_quest.progress == 2 and same_quest.revealed)
	game.queue_free()
	replica.queue_free()
	await process_frame
