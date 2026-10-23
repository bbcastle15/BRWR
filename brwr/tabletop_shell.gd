extends CanvasLayer

# Presentation only. The existing PlayerBoards are moved here, never cloned.
# All card identities/permissions still come from Game's filtered projection.
const Style = preload("res://tabletop_style.gd")
const SIDEBAR_WIDTH := 204.0

var game
var root: Control
var sidebar: VBoxContainer
var sidebar_phase: Label
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
var animated_rest_position := Vector2.ZERO
var animated_rest_scale := Vector2.ONE
var animated_damage_ghost: bool = false
var hidden_damage_cube: Control = null
var damage_display: Dictionary = {}
var damage_event: Dictionary = {}
var defeat_notice: Label
var transient_board := false
var prior_player := -1
var board_choices: Dictionary = {}
var card_overlay: Control
var presentation_art: TextureRect
var presentation_title: Label
var presentation_hint: Label
var presentation_side: Panel
var presentation_rules: RichTextLabel
var card_tween: Tween
var shown_card_serial := -1
var evocation_names_visible := false

func setup(game_node) -> void:
	game = game_node
	layer = 10 # Above world controls, below decisions, hands and inspection.
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
		if board is AvatarBoard: continue
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
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_left = 12
	rail.offset_top = 12
	rail.offset_right = SIDEBAR_WIDTH
	rail.offset_bottom = -12
	rail.add_theme_stylebox_override("panel", Style.fabric_panel())
	root.add_child(rail)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	rail.add_child(column)
	var header := PanelContainer.new()
	header.name = "SidebarHeader"
	var header_style := Style.panel(Color("65563d"), Style.INK)
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", header_style)
	column.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 5)
	header.add_child(heading)
	var title := Label.new()
	title.text = "BLACK ROSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("e2c991"))
	title.add_theme_font_size_override("font_size", 17)
	heading.add_child(title)
	sidebar_phase = Label.new()
	sidebar_phase.name = "Phase"
	sidebar_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar_phase.add_theme_font_size_override("font_size", 14)
	sidebar_phase.add_theme_color_override("font_color", Style.PAPER)
	heading.add_child(sidebar_phase)
	header.minimum_size_changed.connect(_layout.call_deferred)
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
		var crown := TextureRect.new()
		crown.name = "Crown"
		crown.texture = preload("res://assets/tabletop/crown.svg")
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.position = Vector2(126, 61)
		crown.size = Vector2(26, 30)
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
	for entry in [["Cards / Quests / Jinx", _open_hand], ["Lodge · Home", _show_lodge], ["Choices · F10", _show_choices], ["Window / Fullscreen", _window_mode]]:
		var button := Button.new()
		button.text = entry[0]
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(entry[1])
		column.add_child(button)
	var names_button := Button.new()
	names_button.name = "EvocationNames"
	names_button.text = "Evocation names"
	names_button.toggle_mode = true
	names_button.tooltip_text = "Show Evocation names beside their tokens on the Lodge"
	names_button.add_theme_font_size_override("font_size", 13)
	names_button.toggled.connect(_set_evocation_names_visible)
	column.add_child(names_button)
	var exit_button := Button.new()
	exit_button.text = "Main menu" if OS.has_feature("web") else "Exit game"
	exit_button.add_theme_font_size_override("font_size", 13)
	exit_button.pressed.connect(_exit_game)
	column.add_child(exit_button)

func _set_evocation_names_visible(value: bool) -> void:
	evocation_names_visible = value
	for token in game.evocation_tokens.values():
		if is_instance_valid(token):
			token.set_names_visible(value)

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
	background.add_theme_stylebox_override("panel", Style.fabric_panel())
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
	presentation_side = Panel.new()
	presentation_side.name = "ActiveSide"
	presentation_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var highlight := StyleBoxFlat.new()
	highlight.bg_color = Color(1, 0.86, 0.55, 0.025)
	highlight.border_color = Color("ecc779")
	highlight.set_border_width_all(3)
	highlight.set_corner_radius_all(6)
	presentation_side.add_theme_stylebox_override("panel", highlight)
	presentation_art.add_child(presentation_side)
	presentation_rules = RichTextLabel.new()
	presentation_rules.name = "MissingArtRules"
	presentation_rules.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation_rules.offset_left = 24
	presentation_rules.offset_right = -24
	presentation_rules.offset_top = 24
	presentation_rules.offset_bottom = -24
	presentation_rules.add_theme_font_size_override("normal_font_size", 23)
	presentation_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_art.add_child(presentation_rules)
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
	# A reaction/card reveal must not discard damage already dealt.
	if not _has_damage_presentation(): close_board()
	game._close_player_board_spell_preview()
	game._close_reference_card_preview()
	if game.beta_hud != null:
		game.beta_hud.hand_overlay.close_overlay()
	presentation_art.texture = game.ReferenceCardPreview.card_texture(str(data.kind), str(data.id))
	if data.kind == "rooms" and bool(data.get("flipped", false)):
		var rebuilt_path := "res://assets/rooms/rebuilt/%s.png" % str(data.id)
		if ResourceLoader.exists(rebuilt_path):
			presentation_art.texture = load(rebuilt_path)
	var category: String = {"events": "EVENT", "quests": "QUEST", "rooms": "ROOM", "spells": "SPELL", "jinxs": "JINX"}.get(str(data.kind), "")
	presentation_title.text = category + " · " + str(data.title)
	if data.kind == "jinxs":
		presentation_title.text += " · Player %d" % (int(data.player) + 1)
	presentation_side.visible = data.kind == "spells" and not bool(data.get("single", false))
	presentation_rules.visible = presentation_art.texture == null
	presentation_rules.text = ""
	if presentation_rules.visible and data.kind == "spells":
		var spell: SpellCardState = game.spell_database.get_spell(str(data.id))
		if spell != null:
			presentation_rules.text = game.ReferenceCardPreview.describe_rules(spell.get_side(bool(data.get("dark", false))))
		presentation_side.visible = false
	if presentation_side.visible:
		presentation_title.text += " · " + ("Dark" if bool(data.get("dark", false)) else "Light")
	if presentation_hint != null:
		presentation_hint.text = "Click to continue" if bool(data.get("requires_click", false)) else "Click to continue · closes automatically"
		if game.network_session != null and not game.can_acknowledge_card_presentation(game.local_viewer_index):
			presentation_hint.text = "Click to close · waiting for Player %d" % (int(data.get("acknowledge_player", 0)) + 1)
	_layout_card_presentation()
	card_overlay.modulate.a = 0.0
	card_overlay.show()
	card_tween = create_tween()
	card_tween.tween_property(card_overlay, "modulate:a", 1.0, 0.18)

func _dismiss_card_presentation() -> void:
	if card_overlay == null or not card_overlay.visible or game == null:
		return
	if game.network_session != null:
		if game.can_acknowledge_card_presentation(game.local_viewer_index):
			# Keep the modal until the authoritative acknowledgement arrives.
			game.network_session.acknowledge_presentation(shown_card_serial)
		else:
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
	presentation_side.size = Vector2(height * ratio, height * 0.5)
	presentation_side.position = Vector2(0, height * 0.5 if bool(game.card_presentation.get("dark", false)) else 0)

func _layout() -> void:
	if board_overlay == null:
		return
	# Keep every active player visible without scrolling, including 5/6 seats.
	var rail = root.get_node("PlayerRail")
	var column: VBoxContainer = rail.get_child(0)
	var fixed_height: float = 24 + (column.get_child_count() - 1) * 10
	for child in column.get_children():
		if not child is ScrollContainer:
			fixed_height += child.get_combined_minimum_size().y
	var available_rail_height := get_viewport().get_visible_rect().size.y - 24 - fixed_height
	var banner_height := clampf(floorf((available_rail_height - (banners.size() - 1) * 10) / maxf(1, banners.size())) - 2, 42, 102)
	for banner in banners:
		banner.custom_minimum_size.y = banner_height
		banner.get_node("Detail").position.y = 31
		banner.get_node("Detail").size.y = banner_height - 33
		banner.get_node("Detail").visible = banner_height >= 60
		banner.get_node("Crown").position.y = maxf(8, banner_height - 34)
	var available := board_overlay.size - Vector2(28, 64)
	var board_size := Vector2(900, 730)
	if shown_player >= 0 and AvatarRules.is_avatar(game, shown_player):
		board_size = Vector2(1300, 1500)
	if shown_player >= 0 and game.players[shown_player].transformation != null:
		board_size.x = 1180
	var ratio := maxf(0.1, minf(available.x / board_size.x, available.y / board_size.y))
	board_stage.position = Vector2((board_overlay.size.x - board_size.x * ratio) * 0.5, 54)
	board_stage.size = board_size
	board_stage.scale = Vector2.ONE * ratio
	for board in game.player_boards:
		if board is AvatarBoard:
			if board.expanded:
				board.position = Vector2(280, 1500)
				board.rotation = -PI / 2
				board.scale = Vector2.ONE
			continue
		board.position = Vector2.ZERO
		board.scale = Vector2.ONE
	_layout_card_presentation()

func open_board(index: int) -> void:
	if _has_damage_presentation(): return
	_cancel_animation()
	_show_board(index)

func _show_board(index: int) -> void:
	if index < 0 or index >= game.player_boards.size():
		return
	if game.avatar_board != null and game.avatar_board.expanded:
		game.avatar_board.set_expanded(false, game)
	shown_player = index
	for i in game.player_boards.size():
		if game.player_boards[i] is AvatarBoard: continue
		game.player_boards[i].visible = i == index
	if AvatarRules.is_avatar(game, index):
		game.avatar_board.set_expanded(true, board_stage)
		board_title.text = "Possessed · HP %d/%d · %d/%d Commands · gold outline: Health limit" % [game.players[index].mage.get_remaining_health(), game.players[index].mage.health, game.avatar.commands_used, game.avatar.command_limit()]
		board_overlay.show()
		_layout()
		return
	# Quest/cube choices are attached to existing nodes. Opening the window
	# must not rebuild those nodes and erase their pending choice callbacks.
	game.player_boards[index].refresh_spell_slots()
	game.player_boards[index].refresh_action_tokens()
	game.player_boards[index].refresh_transformation()
	board_title.text = game.players[index].player_name + " · " + str(game.players[index].mage_id).capitalize()
	board_overlay.show()
	_layout()

func close_board() -> void:
	_cancel_animation()
	if game.avatar_board != null and game.avatar_board.expanded:
		game.avatar_board.set_expanded(false, game)
	board_overlay.hide()
	shown_player = -1

func reveal_board_choice(index: int) -> void:
	board_choices[index] = true
	if not board_overlay.visible or shown_player != index:
		open_board(index)

func _on_request(_request: Dictionary) -> void:
	if _has_damage_presentation(): return
	# The HUD may already have opened the board needed by this new request.
	# Old addresses are cleared by player_input_resolved; preserve new choices.
	if not board_choices.has(shown_player):
		close_board()

func _process(_delta: float) -> void:
	if game == null or root == null:
		return
	if board_overlay.visible and shown_player >= 0:
		var board_width := 1180.0 if game.players[shown_player].transformation != null else 900.0
		if AvatarRules.is_avatar(game, shown_player): board_width = 1300.0
		if not is_equal_approx(board_stage.size.x, board_width):
			_layout()
	var viewer: int = game.get_ui_viewer_player_index()
	if viewer != observed_viewer:
		observed_viewer = viewer
		if not _has_damage_presentation(): close_board()
		game._close_player_board_spell_preview()
	_refresh_banners()
	if not animated_damage_ghost: sync_card_presentation()
	_observe(true)
	var evocation_resolving: bool = game.resolution_stack.any(func(frame): return frame.get("type") == "evocation_activation")
	if not evocation_resolving and not game.resolution_visual_yield_active and not card_overlay.visible and animation == null and not animation_queue.is_empty() and (game.beta_hud == null or not game.beta_hud.hand_overlay.visible):
		_play_next_animation()

func _refresh_banners() -> void:
	var turn: Dictionary = game.get_turn_presentation()
	sidebar_phase.text = "ROUND %d · %s" % [game.current_round, str(game.current_phase).capitalize()]
	for i in banners.size():
		var player = game.players[i]
		var active := i == int(turn.get("player_index", -1))
		var has_crown: bool = i == game.crown_owner_id
		var signature := str([active, player.mage_id, player.player_name, player.power, player.mage.get_remaining_health(), turn.get("actions_used", 0), board_choices.has(i), has_crown, banners[i].custom_minimum_size.y])
		if banners[i].get_meta("signature", "") == signature:
			continue
		banners[i].set_meta("signature", signature)
		banners[i].get_node("Name").text = player.player_name
		banners[i].get_node("Count").text = "%d/%d" % [int(turn.get("actions_used", 0)), int(turn.get("action_limit", 2))] if active and game.current_phase == game.PHASE_ACTION else ""
		banners[i].get_node("Crown").visible = has_crown
		banners[i].get_node("Detail").text = "%s\nHP %d/%d · Power %d" % [str(player.mage_id).capitalize() if player.mage_id != "" else "Choose a Mage", player.mage.get_remaining_health(), player.mage.health, player.power] if banners[i].custom_minimum_size.y >= 78 else "HP %d · %d PP" % [player.mage.get_remaining_health(), player.power]
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
		var snapshot := {"physical": game.players[i].available_physical_actions, "damage": game.players[i].mage.get_damage(), "slots": {}}
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
				# Markers are public, even on a face-down Trap/Protection. Revealed
				# spells have their own full-screen presentation; do not flip twice.
				if value[0] and str(value[2]) != "" and old.slots[slot_id][2] != value[2]:
					animation_queue.append({"player": i, "node": "SpellSlots/" + ("QuickSpellSlot" if slot_id == "Q" else "SpellSlot" + slot_id) + "/SpellMarker", "kind": "marker", "slot": slot_id})
		observed[i] = snapshot

func _has_damage_presentation() -> bool:
	return animated_damage_ghost or animation_queue.any(func(event): return event.kind == "damage")

func displayed_damage(player_index: int, actual: Array) -> Array:
	return damage_display.get(player_index, actual)

func _refresh_damage_display(index: int) -> void:
	var board = game.player_boards[index]
	if board is AvatarBoard:
		board.create_damage_track()
		if shown_player == index:
			board_title.text = "Possessed · HP %d/%d" % [maxi(0, game.players[index].mage.health - displayed_damage(index, game.players[index].mage.damage_cubes).size()), game.players[index].mage.health]
	else: board.refresh_damage_track()

func queue_damage_placement(player_index: int, previous_damage: int, owners: Array) -> void:
	if not damage_display.has(player_index):
		damage_display[player_index] = owners.slice(0, previous_damage)
	for index in range(previous_damage, owners.size()):
		animation_queue.append({"player": player_index, "node": "DamageTrack/DamageSlot_%d" % index,
			"kind": "damage", "owner": int(owners[index]), "cube_index": index,
			"owners": owners.slice(0, index + 1),
			"defeated": index + 1 >= game.players[player_index].mage.health})

func _play_next_animation() -> void:
	# Pure visual feedback: no rule waits on a Tween, and Close always skips it.
	var event: Dictionary = animation_queue.pop_front()
	var index: int = event.player
	if not transient_board: prior_player = shown_player
	transient_board = true
	layer = 80
	var opening := not board_overlay.visible or shown_player != index
	if opening: _show_board(index)
	animated_node = game.player_boards[index].get_node_or_null(event.node)
	animated_player = index
	animated_damage_ghost = false
	hidden_damage_cube = null
	if event.kind == "damage":
		var board = game.player_boards[index]
		var avatar_target: bool = AvatarRules.is_avatar(game, index)
		var slot = board.get_node_or_null(event.node) if not avatar_target else null
		damage_event = event
		animated_node = preload("res://cube.tscn").instantiate()
		var owner: int = int(event.owner)
		animated_node.cube_color = Color.BLACK if owner < 0 else game.players[owner].color
		animated_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if avatar_target:
			board.add_child(animated_node)
			animated_node.position = board._health_position(int(event.cube_index)) - Vector2(14,14)
			animated_node.scale = Vector2.ONE * 2.0
		elif slot != null:
			slot.add_child(animated_node)
			animated_node.position = Vector2.ZERO
			animated_node.scale = Vector2.ONE * board.DAMAGE_CUBE_SCALE
		else:
			animated_node.free()
			animated_node = null
		animated_damage_ghost = animated_node != null
	if animated_node == null:
		_finish_animation()
		return
	animated_rest_position = animated_node.position
	animated_rest_scale = animated_node.scale
	animated_node.pivot_offset = animated_node.size * 0.5
	animation = create_tween()
	if event.kind == "physical":
		animated_node.text = "+"
		animation.tween_property(animated_node, "scale:x", 0.03, 0.15).set_trans(Tween.TRANS_SINE)
		animation.tween_callback(_refresh_animated_board)
		animation.tween_property(animated_node, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_SINE)
	elif event.kind == "damage":
		# A short placement into the recess, never a falling/bouncing cube.
		animated_node.position -= Vector2(-10, 0) if AvatarRules.is_avatar(game, index) else Vector2(0, 10)
		animated_node.scale = animated_rest_scale * 1.08
		animated_node.modulate.a = 0.0
		if opening: animation.tween_interval(0.32)
		animation.tween_property(animated_node, "modulate:a", 1.0, 0.10)
		animation.parallel().tween_property(animated_node, "position", animated_rest_position, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		animation.parallel().tween_property(animated_node, "scale", animated_rest_scale, 0.22).set_trans(Tween.TRANS_SINE)
		animation.tween_interval(0.10 if not animation_queue.is_empty() and animation_queue[0].kind == "damage" and animation_queue[0].player == index else 0.45)
	else:
		animation.tween_property(animated_node, "modulate:a", 1.0, 0.25)
		animation.tween_interval(0.3)
	animation.tween_callback(_finish_animation)

func _finish_animation() -> void:
	if animated_damage_ghost and not damage_event.is_empty():
		damage_display[animated_player] = damage_event.owners.duplicate()
		_refresh_damage_display(animated_player)
		if bool(damage_event.get("defeated", false)) and not damage_event.get("announced", false):
			damage_event["announced"] = true
			if is_instance_valid(animated_node): animated_node.hide()
			var track = game.player_boards[animated_player].get_node("DamageTrack")
			defeat_notice = Label.new()
			defeat_notice.text = "Player %d defeated" % (animated_player + 1)
			defeat_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			defeat_notice.add_theme_font_size_override("font_size", 32)
			defeat_notice.add_theme_stylebox_override("normal", Style.panel(Style.GOLD, Style.INK, 2))
			board_overlay.add_child(defeat_notice)
			defeat_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			defeat_notice.position = Vector2((board_overlay.size.x - 480) / 2, board_overlay.size.y - 90)
			defeat_notice.size = Vector2(480, 64)
			animation = create_tween()
			for pulse in 3:
				animation.tween_property(track, "modulate", Color(1.6, 1.35, 0.8), 0.18)
				animation.tween_property(track, "modulate", Color.WHITE, 0.22)
			animation.tween_interval(0.8)
			animation.tween_callback(_finish_animation)
			return
	animation = null
	layer = 10
	_refresh_animated_board()
	if is_instance_valid(animated_node):
		animated_node.position = animated_rest_position
		animated_node.scale = animated_rest_scale
		animated_node.modulate = Color.WHITE
	if animated_damage_ghost and is_instance_valid(animated_node): animated_node.queue_free()
	if is_instance_valid(hidden_damage_cube): hidden_damage_cube.show()
	animated_damage_ghost = false
	hidden_damage_cube = null
	animated_node = null
	animated_player = -1
	if not animation_queue.is_empty() and animation_queue[0].kind == "damage":
		_play_next_animation()
		return
	if not animation_queue.any(func(e): return e.kind == "damage"):
		_release_damage_display()
	if transient_board:
		if game.avatar_board != null and game.avatar_board.expanded:
			game.avatar_board.set_expanded(false, game)
		board_overlay.hide()
		shown_player = -1
		if prior_player >= 0:
			_show_board(prior_player)
	transient_board = false

func _cancel_animation() -> void:
	if animation != null:
		animation.kill()
	animation = null
	layer = 10
	_refresh_animated_board()
	if is_instance_valid(animated_node):
		animated_node.position = animated_rest_position
		animated_node.scale = animated_rest_scale
		animated_node.modulate = Color.WHITE
	if animated_damage_ghost and is_instance_valid(animated_node): animated_node.queue_free()
	if is_instance_valid(hidden_damage_cube): hidden_damage_cube.show()
	animated_damage_ghost = false
	hidden_damage_cube = null
	animated_node = null
	animated_player = -1
	transient_board = false
	animation_queue.clear()
	_release_damage_display()

func _release_damage_display() -> void:
	var indices = damage_display.keys()
	damage_display.clear()
	damage_event.clear()
	if is_instance_valid(defeat_notice): defeat_notice.queue_free()
	for index in indices:
		game.player_boards[index].get_node("DamageTrack").modulate = Color.WHITE
		_refresh_damage_display(index)

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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if card_overlay.visible:
			_dismiss_card_presentation()
			get_viewport().set_input_as_handled()
		elif board_overlay.visible:
			close_board()
			get_viewport().set_input_as_handled()
