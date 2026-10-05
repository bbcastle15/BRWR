extends CanvasLayer

# Presentation only. The existing PlayerBoards are moved here, never cloned.
# All card identities/permissions still come from Game's filtered projection.
const Style = preload("res://tabletop_style.gd")
const SIDEBAR_WIDTH := 204.0

var game
var root: Control
var sidebar: VBoxContainer
var banners: Array[Button] = []
var board_overlay: Control
var board_stage: Control
var board_title: Label
var shown_player := -1
var observed_viewer := -2
var observed: Dictionary = {}
var animation_queue: Array[Dictionary] = []
var animation: Tween
var animated_node: Control
var animated_player := -1
var transient_board := false
var prior_player := -1
var board_choices: Dictionary = {}
var card_overlay: Control
var presentation_art: TextureRect
var presentation_title: Label
var presentation_hint: Label
var card_tween: Tween
var shown_card_serial := -1

func setup(game_node) -> void:
	game = game_node
	layer = 0 # Under decision windows, hands and inspection overlays.
	root = Control.new()
	root.name = "TabletopShell"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.make_theme()
	add_child(root)
	_build_sidebar()
	_build_board_overlay()
	_build_card_overlay()
	for board in game.player_boards:
		board.reparent(board_stage)
		board.hide()
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.resized.connect(_layout)
	_layout()
	game.player_input_requested.connect(_on_request)
	game.player_input_resolved.connect(func(_request): board_choices.clear())
	observed_viewer = game.get_ui_viewer_player_index()
	_observe(false)
	_refresh_banners()

func _build_sidebar() -> void:
	var rail := PanelContainer.new()
	rail.name = "PlayerRail"
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = 12
	rail.offset_top = 12
	rail.offset_right = SIDEBAR_WIDTH
	rail.offset_bottom = -12
	rail.add_theme_stylebox_override("panel", Style.panel(Color("4a463d"), Color("101518")))
	root.add_child(rail)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	rail.add_child(column)
	var title := Label.new()
	title.text = "BLACK ROSE"
	title.add_theme_color_override("font_color", Style.GOLD)
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)
	var phase := Label.new()
	phase.name = "Phase"
	phase.add_theme_font_size_override("font_size", 13)
	phase.add_theme_color_override("font_color", Style.MUTED)
	column.add_child(phase)
	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	sidebar = VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 10)
	scroll.add_child(sidebar)
	for i in game.players.size():
		var banner := Button.new()
		banner.name = "PlayerBanner%d" % i
		banner.custom_minimum_size = Vector2(158, 102)
		banner.pressed.connect(open_board.bind(i), CONNECT_DEFERRED)
		sidebar.add_child(banner)
		banners.append(banner)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.position = Vector2(43, 10)
		name_label.size = Vector2(72, 24)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(name_label)
		var icon := Style.marker("mage_power", game.players[i].color, Vector2(26, 26))
		icon.position = Vector2(10, 9)
		banner.add_child(icon)
		var count := Label.new()
		count.name = "Count"
		count.position = Vector2(116, 12)
		count.size = Vector2(35, 22)
		count.add_theme_font_size_override("font_size", 14)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(count)
		var crown := Label.new()
		crown.name = "Crown"
		crown.text = "♛"
		crown.position = Vector2(126, 61)
		crown.size = Vector2(26, 30)
		crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crown.add_theme_font_size_override("font_size", 23)
		crown.add_theme_color_override("font_color", Style.GOLD)
		crown.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.04, 0.95))
		crown.add_theme_constant_override("outline_size", 4)
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crown.hide()
		banner.add_child(crown)
		var detail := Label.new()
		detail.name = "Detail"
		detail.position = Vector2(12, 39)
		detail.size = Vector2(112, 54)
		detail.add_theme_font_size_override("font_size", 13)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(detail)
	for entry in [["Cards / Quests", _open_hand], ["Lodge · Home", _show_lodge], ["Choices · F10", _show_choices], ["Window / Fullscreen", _window_mode]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(entry[1])
		column.add_child(button)
	var exit_button := Button.new()
	exit_button.text = "Main menu" if OS.has_feature("web") else "Exit game"
	exit_button.add_theme_font_size_override("font_size", 13)
	exit_button.pressed.connect(_exit_game)
	column.add_child(exit_button)

func _build_board_overlay() -> void:
	board_overlay = Control.new()
	board_overlay.name = "PlayerBoardOverlay"
	board_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_overlay.offset_left = SIDEBAR_WIDTH + 12
	board_overlay.offset_top = 12
	board_overlay.offset_right = -12
	board_overlay.offset_bottom = -12
	# Lodge model tokens use high z_index values (Evocations currently use 79).
	# Put the modal PlayerBoard above the whole world canvas, otherwise those
	# token Buttons can still win hit-testing through the open board.
	board_overlay.z_index = 200
	# When a PlayerBoard is open, the overlay must own the entire table input
	# region so clicks can never fall through to Lodge models underneath.
	board_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(board_overlay)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.add_theme_stylebox_override("panel", Style.panel(Style.GOLD, Color("0d1216")))
	board_overlay.add_child(background)
	board_title = Label.new()
	board_title.position = Vector2(22, 12)
	board_title.add_theme_font_size_override("font_size", 21)
	board_overlay.add_child(board_title)
	var close := Button.new()
	close.text = "Lodge  ×"
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -150
	close.offset_right = -12
	close.offset_top = 8
	close.offset_bottom = 48
	close.pressed.connect(close_board)
	board_overlay.add_child(close)
	board_stage = Control.new()
	board_stage.name = "BoardStage"
	board_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	board_overlay.add_child(board_stage)
	board_overlay.hide()

func _build_card_overlay() -> void:
	var card_layer := CanvasLayer.new()
	card_layer.layer = 145
	add_child(card_layer)
	card_overlay = Control.new()
	card_overlay.name = "ResolvingCard"
	card_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_layer.add_child(card_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.04, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_overlay.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	presentation_title = Label.new()
	presentation_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presentation_title.add_theme_font_size_override("font_size", 22)
	presentation_title.add_theme_color_override("font_color", Style.PAPER)
	column.add_child(presentation_title)
	presentation_art = TextureRect.new()
	presentation_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	presentation_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	presentation_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(presentation_art)
	presentation_hint = Label.new()
	presentation_hint.text = "Click to continue"
	presentation_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	presentation_hint.add_theme_font_size_override("font_size", 16)
	presentation_hint.add_theme_color_override("font_color", Style.GOLD)
	presentation_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(presentation_hint)
	var dismiss := Button.new()
	dismiss.name = "PresentationDismiss"
	dismiss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dismiss.flat = true
	dismiss.text = ""
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.mouse_filter = Control.MOUSE_FILTER_STOP
	dismiss.pressed.connect(_dismiss_card_presentation)
	card_overlay.add_child(dismiss)
	card_overlay.hide()

func sync_card_presentation() -> void:
	var data: Dictionary = game.card_presentation
	var serial: int = int(data.get("serial", -1))
	if serial == shown_card_serial:
		return
	shown_card_serial = serial
	if card_tween != null:
		card_tween.kill()
	if data.is_empty():
		card_overlay.hide()
		return
	close_board()
	game._close_player_board_spell_preview()
	game._close_reference_card_preview()
	if game.beta_hud != null:
		game.beta_hud.hand_overlay.close_overlay()
	presentation_art.texture = game.ReferenceCardPreview.card_texture(str(data.kind), str(data.id))
	var category := "EVENT" if data.kind == "events" else "QUEST"
	presentation_title.text = category + " · " + str(data.title)
	if presentation_hint != null:
		presentation_hint.text = "Click to continue" if bool(data.get("requires_click", false)) else "Click to continue · closes automatically"
	_layout_card_presentation()
	card_overlay.modulate.a = 0.0
	card_overlay.show()
	card_tween = create_tween()
	card_tween.tween_property(card_overlay, "modulate:a", 1.0, 0.18)

func _dismiss_card_presentation() -> void:
	if card_overlay == null or not card_overlay.visible or game == null:
		return
	if game.network_client:
		# Client acknowledgement is local-only; the authoritative host controls
		# when resolution continues. Do not re-show the same serial.
		card_overlay.hide()
		return
	game.dismiss_card_presentation(shown_card_serial)


func _layout_card_presentation() -> void:
	if presentation_art == null:
		return
	var view := get_viewport().get_visible_rect().size
	var ratio := presentation_art.texture.get_size().aspect() if presentation_art.texture != null else 0.67
	var height := minf(view.y - 110, (view.x - 64) / ratio)
	presentation_art.custom_minimum_size = Vector2(height * ratio, height)

func _layout() -> void:
	if board_overlay == null:
		return
	var available := board_overlay.size - Vector2(28, 64)
	var board_size := Vector2(900, 730)
	var ratio := maxf(0.1, minf(available.x / board_size.x, available.y / board_size.y))
	board_stage.position = Vector2((board_overlay.size.x - board_size.x * ratio) * 0.5, 54)
	board_stage.size = board_size
	board_stage.scale = Vector2.ONE * ratio
	for board in game.player_boards:
		board.position = Vector2.ZERO
		board.scale = Vector2.ONE
	_layout_card_presentation()

func open_board(index: int) -> void:
	_cancel_animation()
	_show_board(index)

func _show_board(index: int) -> void:
	if index < 0 or index >= game.player_boards.size():
		return
	shown_player = index
	for i in game.player_boards.size():
		game.player_boards[i].visible = i == index
	# Quest/cube choices are attached to existing nodes. Opening the window
	# must not rebuild those nodes and erase their pending choice callbacks.
	game.player_boards[index].refresh_spell_slots()
	game.player_boards[index].refresh_action_tokens()
	board_title.text = game.players[index].player_name + " · " + str(game.players[index].mage_id).capitalize()
	board_overlay.show()
	_layout()

func close_board() -> void:
	_cancel_animation()
	board_overlay.hide()
	shown_player = -1

func reveal_board_choice(index: int) -> void:
	board_choices[index] = true
	if not board_overlay.visible:
		open_board(index)

func _on_request(_request: Dictionary) -> void:
	# A new decision must never be obscured by an old player's personal view.
	close_board()
	board_choices.clear()

func _process(_delta: float) -> void:
	if game == null or root == null:
		return
	var viewer: int = game.get_ui_viewer_player_index()
	if viewer != observed_viewer:
		observed_viewer = viewer
		close_board()
		game._close_player_board_spell_preview()
		animation_queue.clear()
	_refresh_banners()
	sync_card_presentation()
	_observe(true)
	if not card_overlay.visible and animation == null and not animation_queue.is_empty() and (game.beta_hud == null or not game.beta_hud.hand_overlay.visible):
		_play_next_animation()

func _refresh_banners() -> void:
	var turn: Dictionary = game.get_turn_presentation()
	root.get_node("PlayerRail").get_child(0).get_node("Phase").text = "ROUND %d · %s" % [game.current_round, str(game.current_phase).capitalize()]
	for i in banners.size():
		var player = game.players[i]
		var active := i == int(turn.get("player_index", -1))
		var has_crown: bool = i == game.crown_owner_id
		var signature := str([active, player.mage_id, player.player_name, player.power, player.mage.get_remaining_health(), turn.get("actions_used", 0), board_choices.has(i), has_crown])
		if banners[i].get_meta("signature", "") == signature:
			continue
		banners[i].set_meta("signature", signature)
		banners[i].get_node("Name").text = player.player_name
		banners[i].get_node("Count").text = "%d/2" % int(turn.get("actions_used", 0)) if active and game.current_phase == game.PHASE_ACTION else ""
		banners[i].get_node("Crown").visible = has_crown
		banners[i].get_node("Detail").text = "%s\nHP %d/%d · Power %d" % [str(player.mage_id).capitalize() if player.mage_id != "" else "Choose a Mage", player.mage.get_remaining_health(), player.mage.health, player.power]
		var edge: Color = player.color.lerp(Color.WHITE, 0.22)
		var normal := Style.panel(edge if active or board_choices.has(i) else edge.darkened(0.5), Color("252925") if active else Style.INK, 3 if active else 1)
		normal.border_width_left = 6
		if active:
			normal.shadow_color = Color(edge, 0.25)
			normal.shadow_size = 12
		banners[i].add_theme_stylebox_override("normal", normal)
		banners[i].add_theme_stylebox_override("hover", Style.panel(edge, Color("2a3031"), 2))
		banners[i].tooltip_text = "Open PlayerBoard" + (" · available targets" if board_choices.has(i) else "")

func _observe(animate: bool) -> void:
	for i in game.players.size():
		var snapshot := {"physical": game.players[i].available_physical_actions, "slots": {}}
		for slot_id in ["Q", "I", "II", "III"]:
			var data: Dictionary = game.get_player_board_spell_slot_data(i, slot_id)
			# This signature deliberately contains no private identity or active side.
			snapshot.slots[slot_id] = [not data.is_empty(), data.get("public", false), data.get("marker", "")]
		if animate and observed.has(i):
			var old: Dictionary = observed[i]
			if snapshot.physical < old.physical:
				animation_queue.append({"player": i, "node": "PhysicalAction" + str(snapshot.physical), "kind": "physical"})
			for slot_id in snapshot.slots:
				var value: Array = snapshot.slots[slot_id]
				if value[0] and old.slots[slot_id] != value:
					animation_queue.append({"player": i, "node": "SpellSlots/" + ("QuickSpellSlot" if slot_id == "Q" else "SpellSlot" + slot_id), "kind": "spell", "slot": slot_id})
		observed[i] = snapshot

func _play_next_animation() -> void:
	# Pure visual feedback: no rule waits on a Tween, and Close always skips it.
	var event: Dictionary = animation_queue.pop_front()
	var index: int = event.player
	prior_player = shown_player
	transient_board = true
	layer = 80
	_show_board(index)
	animated_node = game.player_boards[index].get_node_or_null(event.node)
	animated_player = index
	if animated_node == null:
		_finish_animation()
		return
	animated_node.pivot_offset = animated_node.size * 0.5
	var flip: bool = event.kind == "physical" or bool(game.get_player_board_spell_slot_data(index, str(event.get("slot", ""))).get("public", false))
	animation = create_tween()
	if flip:
		if event.kind == "physical":
			animated_node.text = "+"
		else:
			animated_node.get_node("CardArt").hide()
			animated_node.get_node("ActiveSide").hide()
			animated_node.get_node("CardBack").show()
		animation.tween_property(animated_node, "scale:x", 0.03, 0.15).set_trans(Tween.TRANS_SINE)
		animation.tween_callback(_refresh_animated_board)
		animation.tween_property(animated_node, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	else:
		animated_node.modulate = Color(1.4, 1.3, 1.0)
		animation.tween_property(animated_node, "modulate", Color.WHITE, 0.4)
	animation.tween_interval(0.75)
	animation.tween_callback(_finish_animation)

func _finish_animation() -> void:
	animation = null
	layer = 0
	_refresh_animated_board()
	if is_instance_valid(animated_node):
		animated_node.scale = Vector2.ONE
		animated_node.modulate = Color.WHITE
	animated_node = null
	animated_player = -1
	if transient_board:
		board_overlay.hide()
		shown_player = -1
		if prior_player >= 0:
			_show_board(prior_player)
	transient_board = false

func _cancel_animation() -> void:
	if animation != null:
		animation.kill()
	animation = null
	layer = 0
	_refresh_animated_board()
	if is_instance_valid(animated_node):
		animated_node.scale = Vector2.ONE
		animated_node.modulate = Color.WHITE
	animated_node = null
	animated_player = -1
	transient_board = false
	animation_queue.clear()

func _refresh_animated_board() -> void:
	if animated_player >= 0 and animated_player < game.player_boards.size():
		game.player_boards[animated_player].refresh_spell_slots()
		game.player_boards[animated_player].refresh_action_tokens()

func _open_hand() -> void:
	close_board()
	if game.beta_hud != null:
		game.beta_hud._open_hand_overlay()

func _show_choices() -> void:
	if game.beta_hud != null:
		game.beta_hud._toggle_panel()

func _show_lodge() -> void:
	close_board()
	if game.beta_hud != null:
		game.beta_hud.hand_overlay.close_overlay()
	var camera = game.get_node_or_null("TableCamera")
	if camera != null:
		camera.reset_view()

func _window_mode() -> void:
	if game.beta_hud != null:
		game.beta_hud._toggle_window_mode()

func _exit_game() -> void:
	if OS.has_feature("web"):
		multiplayer.multiplayer_peer = null
		get_tree().reload_current_scene()
	else:
		get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and board_overlay.visible:
		close_board()
		get_viewport().set_input_as_handled()
