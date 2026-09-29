extends SceneTree

var session
var last_revision := -1
var choices := 0
var elapsed := 0.0
var host_mode := false
var action_seen_at := -1.0
var stale_revision := -1
var stale_sent_at := -1.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	host_mode = OS.get_cmdline_user_args().has("host")
	session = load("res://online_session.gd").new()
	session.name = "OnlineSession"
	root.add_child(session)
	if host_mode:
		assert(session.host() == OK)
		session.room_code = "123456"
	else:
		assert(session.join("127.0.0.1", "123456") == OK)

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > 40:
		push_error("ONLINE PLAYTEST TIMEOUT choices=" + str(choices))
		quit(1)
		return false
	if session == null or session.game == null: return false
	var game = session.game
	if game.beta_hud == null: return false
	if not host_mode:
		assert(game.get_ui_viewer_player_index() == 1)
		assert(game.players[0].hand.all(func(card): return card == null))
		for slot in ["Q", "I", "II", "III"]:
			var card: Dictionary = game.get_player_board_spell_slot_data(0, slot)
			if not card.get("public", false): assert(not card.has("id"))
	var request: Dictionary = game.pending_input
	if game.current_phase == "action" and game.players.all(func(player): return not player.mage.in_cell):
		if action_seen_at < 0:
			action_seen_at = elapsed
		if not host_mode or elapsed - action_seen_at > 3.0:
			print("ONLINE PLAYTEST PASS ", "HOST" if host_mode else "CLIENT", " choices=", choices)
			quit()
		return false
	if not game.waiting_for_player_input: return false
	var actor: int = int(request.get("player_index", -1))
	if actor != game.local_viewer_index or game.input_revision == last_revision: return false
	assert(not session.submit_local(1 - actor, {}), "Cannot submit on behalf of opponent")
	if not host_mode:
		if stale_sent_at < 0:
			stale_revision = game.input_revision
			stale_sent_at = elapsed
			session._choose.rpc_id(1, stale_revision - 1, {"mage_id": "angela"})
			return false
		if elapsed - stale_sent_at < 0.5: return false
		if last_revision < 0:
			assert(game.input_revision == stale_revision, "Stale command changed the game")
	var payload := {}
	match str(request.get("type", "")):
		"starting_mage_choice": payload = {"mage_id": request.available_mages[0].id}
		"starting_school_choice": payload = {"school_id": request.available_schools[0].id}
		"starting_grimoire_choice": payload = {"grimoire_id": request.options[0].id}
		"black_rose_optional_quest_discard": payload = {"quest_index": -1}
		"study_choose_schools": payload = {"school_ids": [request.active_school_ids[0], request.active_school_ids[0], request.active_school_ids[0], request.active_school_ids[0]]}
		"study_keep_cards": payload = {"keep_indices": [0, 1]}
		"study_optional_discard": payload = {"hand_index": -1}
		"study_hand_limit":
			var indices: Array = []
			for i in int(request.get("discard_count", 1)): indices.append(i)
			payload = {"hand_indices": indices}
		"preparation": payload = {"ready_hand_indices": [0, 1, 2], "ready_dark_sides": [false, false, false], "quick_hand_index": 3, "quick_dark_side": false}
		"action_activation_step":
			var options: Array = request.get("options", [])
			var selected: Dictionary = {}
			for option in options:
				if option.get("kind") == "finish": selected = option
			if selected.is_empty():
				for option in options:
					if option.get("action", {}).get("type") == "explore" and not option.action.get("activate_room", false):
						selected = option
						break
			assert(not selected.is_empty(), "Expected a physical action or finish")
			payload = {"token": selected.token}
		"effect_choice": payload = {"selection": [request.options[0].token]}
		_:
			print("REQUEST TO HANDLE ", request)
			quit(2)
			return false
	print("TEST INPUT ", request.type, " ", payload)
	last_revision = game.input_revision
	assert(session.submit_local(actor, payload))
	choices += 1
	return false
