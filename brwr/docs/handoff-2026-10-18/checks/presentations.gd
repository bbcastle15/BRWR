extends SceneTree

var TASK := OS.get_user_data_dir() + "/"
const Tokens = preload("res://evocation_token.gd")
var game
var checks := 0
var failures: Array[String] = []

func _initialize():
	call_deferred("run")
	create_timer(90).timeout.connect(func(): push_error("Presentation check timed out"); quit(2))

func expect(value: bool, message: String):
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle():
	for i in 5: await process_frame

func capture(name_value: String):
	if DisplayServer.get_name() == "headless": return
	await settle()
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(TASK + name_value + ".png")

func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://game.tscn").instantiate()
	game.beta_force_fullscreen = false
	game.auto_start_game_flow = false
	game.network_client = true
	root.add_child(game)
	while game.beta_hud == null: await process_frame
	await settle()
	game.network_client = false
	game.local_viewer_index = 0
	game.current_phase = game.PHASE_ACTION
	game.game_flow_active = false
	for player in game.players:
		player.mage.in_cell = false
		player.mage.room_id = "arena"
		player.mage.room_coord = game.room_id_to_coord("arena")
	var shell = game.table_shell
	expect(game.is_school_complete("heka"), "Heka is complete at runtime")
	expect(game.get_playable_school_ids().has("heka"), "Heka enters playable school pool")
	var heka_count := 0
	for spell in game.spell_database.get_school_spells("heka"):
		if spell.personal or spell.forgotten: continue
		heka_count += 1
		expect(SpellArtResolver.get_texture(spell.id, "heka") != null, "Heka art: " + spell.id)
		for dark in [false, true]:
			expect(game._school_material_available(spell.get_side(dark)), "Heka material: " + spell.id)
	expect(heka_count == 12, "All twelve Heka spells")
	print("PLAYABLE SCHOOLS: ", game.get_playable_school_ids())
	# A normal spell waits on its presentation BEFORE resolving its effect.
	var spell := SpellCardState.new("misfortune", "Misfortune", "heka",
		{"type":"contingency", "target":"self", "effects":[{"type":"gain_power", "amount":2}]},
		{"type":"contingency", "target":"self", "effects":[{"type":"gain_power", "amount":3}]})
	var initial_power: int = game.players[0].power
	game.queue_resolution({"type":"spell_resolution", "spell":spell, "use_dark_side":true,
		"step":"prepare", "context":{"game":game,"caster_id":0,"caster_room_id":"arena"},"sequence_index":0})
	await settle()
	expect(shell.card_overlay.visible, "Cast spell is full-screen")
	expect(game.players[0].power == initial_power, "Effect waits for click")
	expect(game.card_presentation.get("requires_click", false), "Spell has no auto-close timer")
	expect(shell.presentation_side.visible and shell.presentation_side.position.y > 0, "Dark half is highlighted")
	await capture("spell-dark")
	await create_timer(2.0).timeout
	expect(shell.card_overlay.visible and game.players[0].power == initial_power, "Spell still waits after former timeout")
	var serial: int = game.card_presentation.serial
	expect(not game.dismiss_card_presentation(serial - 1), "Stale acknowledgement ignored")
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = Vector2(800,450)
		click.global_position = click.position
		root.push_input(click)
		await process_frame
	await settle()
	expect(game.players[0].power == initial_power + 3, "Click resolves active side once")
	expect(game.card_presentation.is_empty() and not shell.card_overlay.visible, "Presentation closes")
	game.dismiss_card_presentation(serial)
	expect(game.players[0].power == initial_power + 3, "Duplicate click cannot resolve twice")
	game.clear_player_input()
	game.resolution_stack.clear()
	# The public arm marker must animate without disclosing the hidden card.
	var trap: SpellCardState = game.spell_database.get_spell("cursed_hieroglyphics")
	var ready := ReadySpellState.new(trap, false)
	game.players[0].ready_spells.assign([ready])
	game.player_board_spell_slots[0] = {"I":{"spell":trap,"state":"prepared","use_dark_side":false}}
	shell._observe(false)
	game.queue_resolution({"type":"spell_cast", "player_index":0, "ready_spell":ready,"source":"ready","context":{}})
	await settle()
	expect(game.card_presentation.is_empty(), "Setting a Trap does not reveal its card")
	var public_slot: Dictionary = game.get_player_board_spell_slot_data(0,"I",1)
	expect(public_slot.get("marker") == "TRAP" and not public_slot.has("id"), "Opponent sees token only")
	expect(shell.board_overlay.visible and shell.shown_player == 0, "Arming highlights caster PlayerBoard")
	expect(is_instance_valid(shell.animated_node) and shell.animated_node.name == "SpellMarker", "Actual placed token animates")
	await create_timer(0.3).timeout
	await capture("trap-marker")
	await create_timer(1.1).timeout
	shell.close_board()
	game.clear_player_input()
	game.resolution_stack.clear()
	# Trigger presentation is public, unlike setting.
	var active = game.players[0].active_spells[0]
	var frame := {"type":"trigger_spell", "active_spell":active}
	expect(game._present_resolution_card(frame), "Triggered Trap gets a presentation")
	expect(game.card_presentation.id == trap.id, "Revealed Trap identity is public")
	expect(not game._present_resolution_card(frame), "One presentation per resolution frame")
	game.dismiss_card_presentation()
	# Online acknowledgement uses the caster's authenticated seat and serial.
	var session = load("res://online_session.gd").new()
	root.add_child(session)
	session.game = game
	session.hosting = true
	session.connected = true
	session.peer_players = {"caster":1, "other":0}
	session.receiving = {"caster":true, "other":true}
	game.network_session = session
	game.card_presentation = {"serial":200,"kind":"spells","id":"misfortune","title":"Misfortune","player":1,"acknowledge_player":1,"requires_click":true,"dark":false}
	shell.sync_card_presentation()
	expect(not session.acknowledge_presentation(200), "Host cannot acknowledge other caster")
	session._handle_game_message("other",{"op":"ack_presentation","serial":200})
	expect(not game.card_presentation.is_empty(), "Other seat cannot advance presentation")
	session._handle_game_message("caster",{"op":"ack_presentation"})
	expect(not game.card_presentation.is_empty(), "Missing network serial rejected")
	session._handle_game_message("caster",{"op":"ack_presentation","serial":199})
	expect(not game.card_presentation.is_empty(), "Stale network serial rejected")
	session._handle_game_message("caster",{"op":"ack_presentation","serial":200})
	expect(game.card_presentation.is_empty(), "Authenticated caster click advances resolution")
	game.network_session = null
	session.connected = false
	session.queue_free()
	# Markers traverse real track cells and settle to the existing layout.
	var power = game.get_node("PowerBoard")
	power.instant_updates = true
	game.set_player_power(0,11)
	power.instant_updates = false
	var start: Vector2 = power.player_markers[0].position
	game.set_player_power(0,13)
	expect(power.player_markers[0].position.is_equal_approx(start), "Score does not teleport")
	await create_timer(0.1).timeout
	expect(not power.player_markers[0].position.is_equal_approx(start), "Score marker slides")
	await create_timer(0.6).timeout
	expect(power.player_markers[0].position.is_equal_approx(power.get_power_position(13)), "Marker reaches exact cell across column break")
	game.set_player_power(1,13)
	await create_timer(0.9).timeout
	var midpoint: Vector2 = (power.player_markers[0].position + power.player_markers[1].position) / 2.0
	expect(midpoint.is_equal_approx(power.get_power_position(13)), "Shared score stays centered")
	var camera = game.get_node("TableCamera")
	camera.reset_view()
	var camera_position: Vector2 = camera.position
	var camera_zoom: Vector2 = camera.zoom
	game.add_black_rose_power(2)
	await create_timer(0.4).timeout
	expect(camera.power_focus != null and camera.zoom.x > camera_zoom.x, "Black Rose gain zooms to PowerBoard")
	await capture("rose-power")
	await create_timer(1.4).timeout
	expect(camera.position.is_equal_approx(camera_position) and camera.zoom.is_equal_approx(camera_zoom), "Camera restores previous view")
	expect(power.black_rose_marker.position.is_equal_approx(power.get_power_position(2)), "Rose reaches exact power cell")
	shell.open_board(0)
	var covered_start: Vector2 = power.player_markers[0].position
	game.set_player_power(0,14)
	await create_timer(0.3).timeout
	expect(power.player_markers[0].position.is_equal_approx(covered_start) and power.markers_dirty, "Power feedback waits for modal to close")
	shell.close_board()
	await create_timer(0.6).timeout
	expect(power.player_markers[0].position.is_equal_approx(power.get_power_position(14)), "Deferred score remains visible and reaches cell")
	# Every actual model gets a portrait. Equipment remains excluded by game.
	var models: Array = game.evocation_database.get_all_evocations().filter(func(data): return data.archetype != "equipment")
	for data in models:
		var texture: Texture2D = Tokens.portrait_texture(data.id)
		expect(texture != null, "Portrait available: " + data.id)
		if texture is AtlasTexture:
			expect(Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(texture.region), "Portrait stays inside source: " + data.id)
	await render_catalog(models)
	game.queue_free()
	await process_frame
	print("PRESENTATION/HEKA CHECK: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func render_catalog(models: Array):
	if DisplayServer.get_name() == "headless": return
	var layer := CanvasLayer.new()
	layer.layer = 250
	root.add_child(layer)
	for page in ceili(models.size()/12.0):
		var stage := Control.new()
		layer.add_child(stage)
		var bg := ColorRect.new()
		bg.size = Vector2(1600,900)
		bg.color = Color("13191c")
		stage.add_child(bg)
		for index in 12:
			var n := page*12+index
			if n >= models.size(): break
			var data: Dictionary = models[n]
			var origin := Vector2((index%4)*400, (index/4)*300)
			var label := Label.new()
			label.position = origin + Vector2(10,5)
			label.text = data.name
			label.add_theme_font_size_override("font_size",22)
			stage.add_child(label)
			var art := TextureRect.new()
			art.position = origin + Vector2(0,45)
			art.size = Vector2(270,205)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.texture = game.ReferenceCardPreview.card_texture("evocations", data.id)
			if data.id == "gaea": art.texture = load("res://assets/spells/gaea.png")
			if data.id == "janara": art.texture = load("res://assets/spells/woodland_spirit.png")
			stage.add_child(art)
			var token = Tokens.new()
			token.position = origin+Vector2(335,130)
			token.scale = Vector2.ONE*2.6
			stage.add_child(token)
			token.setup(data.id,data.name,0,Color("ba473b"),1)
			var actual = Tokens.new()
			actual.position = origin+Vector2(335,240)
			stage.add_child(actual)
			actual.setup(data.id,data.name,1,Color("5868cf"),2)
		await capture("portrait-catalog-%d" % page)
		stage.queue_free()
		await process_frame
	layer.queue_free()
