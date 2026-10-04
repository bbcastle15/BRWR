extends SceneTree

var failures := 0
var checks := 0
var screenshot_mode := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(6): await process_frame

func make_game(client: bool):
	var game = load("res://game.tscn").instantiate()
	game.auto_start_game_flow = false
	game.enable_beta_hud = false
	game.beta_force_fullscreen = false
	game.network_client = client
	game.local_viewer_index = 1 if client else 0
	game.game_seed = 1232
	root.add_child(game)
	await settle()
	return game

func shot(name: String) -> void:
	if not screenshot_mode: return
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/death-school/" + name + ".png")

func run() -> void:
	create_timer(35).timeout.connect(func(): push_error("Death UI/network timed out"); quit(1))
	screenshot_mode = OS.get_cmdline_user_args().has("screenshots")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	var host = await make_game(false)
	var client = await make_game(true)
	host.assign_mage_to_player(0, "mors")
	host.assign_mage_to_player(1, "angela")
	for player in host.players:
		player.mage.in_cell = false
		player.mage.room_id = "forge"
		player.mage.room_coord = host.room_id_to_coord("forge")
	for card in host.spell_database.spells.values():
		if card.school_id != "death" and card.id != "consuming_soul": continue
		var art := SpellArtResolver.get_texture(card.id, card.school_id)
		check(art != null, "Spell image loaded: " + card.id)
		if art != null:
			check(art.get_width() >= 1000 and is_equal_approx(art.get_size().aspect(), 2.0 / 3.0), "Portrait HD proportions: " + card.id)
	host.players[0].hand.append(host.clone_spell_card(host.spell_database.get_spell("tearing")))
	host._set_player_board_spell_slot(0, "I", host.players[0].hand[0], false, "prepared")
	host.effect_resolver.resolve_effect({"type": "assign_destiny", "amount": 3}, {"game": host, "caster_id": 1, "target_player_index": 0})
	var board = host.player_boards[0]
	check(board.get_node("MageCardSlot/MageArt").texture.resource_path.ends_with("mors.png"), "Mors uses her own portrait")
	var tokens = board.get_node("DestinyTokens")
	check(tokens.get_child_count() == 3, "All assigned Destiny visible on board")
	for token in tokens.get_children():
		check(token.texture != null and token.get_child(0).cube_color == host.players[1].color, "Destiny displays real owner cube")
	# The transport serializes only the same public projection used by online.
	var projection = load("res://network_projection.gd")
	var packet: Dictionary = bytes_to_var(var_to_bytes(projection.build(host, 1)))
	projection.apply(client, packet)
	check(client.players[0].mage.destiny_tokens == [1, 1, 1], "Destiny survives network round-trip")
	check(client.players[0].hand[0] == null and not client.get_player_board_spell_slot_data(0, "I").has("id"), "Destiny sync preserves private Spell visibility")
	check(client.player_boards[0].get_node("DestinyTokens").get_child_count() == 3, "Client renders public Destiny")
	host.deal_damage(1, 0, 11)
	packet = bytes_to_var(var_to_bytes(projection.build(host, 1)))
	check(packet.pending_input.get("choice_kind") == "destiny_resolution" and packet.pending_input.player_index == 1, "Online choice belongs to Destiny owner")
	check(not host.submit_effect_choice(0, ["destiny:0"]), "Other seat cannot resolve owner's tokens")
	check(host.submit_effect_choice(1, ["destiny:0"]), "Correct seat can retain assigned Destiny")
	packet = bytes_to_var(var_to_bytes(projection.build(host, 1)))
	projection.apply(client, packet)
	check(client.players[0].mage.in_cell and client.players[0].mage.destiny_tokens.size() == 3, "Unresolved Destiny remains public after defeat")
	client.queue_free()
	await settle()
	host.table_shell = load("res://tabletop_shell.gd").new()
	host.add_child(host.table_shell)
	host.table_shell.setup(host)
	host.beta_hud = load("res://beta_hud.gd").new()
	host.add_child(host.beta_hud)
	host.beta_hud.setup(host)
	host.refresh_all_player_boards()
	host.table_shell.open_board(0)
	await shot("mors-board")
	host.table_shell.close_board()
	host.beta_hud.present_pending_request({"type": "starting_school_choice", "player_index": 0,
		"available_schools": [{"id": "agony", "name": "Agony"}, {"id": "alchemy", "name": "Alchemy"}, {"id": "death", "name": "Death"}]})
	await settle()
	var row = host.beta_hud.content.get_node("ObjectChoices").get_child(0)
	check(row.get_child_count() == 3, "Death appears beside existing School cards")
	var school_art: Texture2D = row.get_child(2).get_child(0).get_child(0).texture
	check(school_art != null and school_art.resource_path.ends_with("death.png"), "Death School rules card loads in setup")
	await shot("death-school-choice")
	host.queue_free()
	await process_frame
	print("DEATH UI / NETWORK: %d checks; %d failures" % [checks, failures])
	quit(failures)
