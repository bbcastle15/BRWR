class_name AvatarBoard
extends Node2D

# The same Avatar Board stays on the table and moves into the modal for
# inspection. It reads PlayerState directly; there is no Avatar PlayerBoard.
const TIP := Vector2(21, 350)
const OUTLINE := [Vector2(21,350),Vector2(223,0),Vector2(1450,0),Vector2(1450,700),Vector2(223,700)]
const POWER_BOARD_ART = preload("res://assets/boards/power_board_reference.png")
const SHEET := Rect2(698, 44, 412, 602)
const COMMANDS := Rect2(267, 52, 372, 276)
const MEMORIES := Rect2(267, 365, 372, 273)
var game
var signature := ""
var expanded := false
var cards_root: Node2D
var damage_track: Node2D
var table_transform := Transform2D.IDENTITY

func setup(owner_game) -> void:
	game = owner_game
	name = "AvatarBoard"
	var body := Polygon2D.new()
	body.name = "BoardFrame"
	body.texture = preload("res://assets/avatars/possessed/production/board.svg")
	body.polygon = OUTLINE
	body.uv = OUTLINE
	body.show_behind_parent = true
	add_child(body)
	var material := Polygon2D.new()
	material.name = "BoardMaterial"
	material.texture = preload("res://assets/avatars/possessed/production/board_material.png")
	material.polygon = OUTLINE
	var material_uv := PackedVector2Array()
	for point in OUTLINE:
		material_uv.append(point * material.texture.get_size() / Vector2(1450,700))
	material.uv = material_uv
	material.show_behind_parent = true
	add_child(material)
	move_child(material, 0)
	cards_root = Node2D.new()
	cards_root.name = "EvocationCards"
	add_child(cards_root)
	damage_track = Node2D.new()
	damage_track.name = "DamageTrack"
	add_child(damage_track)
	reposition()
	refresh()

func set_expanded(value: bool, parent: Node) -> void:
	expanded = value
	reparent(parent)
	if value:
		position = Vector2(280, 1500)
		rotation = -PI / 2
		scale = Vector2.ONE
	else: reposition()
	_update_hitboxes()

func _update_hitboxes() -> void:
	for card in cards_root.get_children():
		if card is Control:
			card.mouse_filter = Control.MOUSE_FILTER_STOP if expanded else Control.MOUSE_FILTER_IGNORE
			if card.name == "AvatarJinxes":
				card.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED if expanded else Control.MOUSE_BEHAVIOR_DISABLED
			if card.has_meta("upright_in_portrait"):
				card.pivot_offset = card.size * 0.5
				card.rotation = PI / 2 if expanded else 0.0
			else:
				for child in card.get_children():
					if child is Label:
						child.pivot_offset = Vector2.ZERO
						child.position = Vector2(card.size.x - 8, 8) if expanded else Vector2(8,8)
						child.rotation = PI / 2 if expanded else 0.0

func refresh() -> void:
	if game == null or cards_root == null: return
	var player: PlayerState = game.players[game.avatar.player_index]
	var evocations: Array = []
	for ev in player.evocations: evocations.append([ev.get_instance_id(), ev.board_number, ev.damage_cubes, ev.room_id])
	var updated := str([player.mage.damage_cubes, player.mage.destiny_tokens, player.mage.infectio_tokens, player.get_mage_speed(), game.current_moon, game.avatar.public_data(), player.completed_quests.map(func(q): return q.get_id()), evocations, player.mage.jinxes, player.trophies])
	if signature == updated: return
	signature = updated
	for card in cards_root.get_children():
		cards_root.remove_child(card)
		card.queue_free()
	var preview = game._reference_card_preview()
	_add_card("avatars", "possessed", "Possessed · Dominion", SHEET,
		func():
			if not expanded and game.table_shell != null:
				game.table_shell.open_board(game.avatar.player_index)
			else:
				preview.show_card("avatars", "possessed", "Possessed · Dominion", ""))
	var back_id := "command_back_%d" % clampi(game.current_moon, 1, 3)
	_add_card("avatars", back_id, "Command deck · Moon %d · %d cards" % [game.current_moon, player.grimoire.size()], COMMANDS,
		func(): preview.show_card("avatars", back_id, "Command deck · Moon %d" % game.current_moon,
			"%d cards. Hidden faces and order. Reaction: %s" % [player.grimoire.size(), str(game.avatar.public_data().reaction)]))
	if not player.memories.is_empty():
		var discard = _add_card("spells", player.memories.back().id, "Memories", MEMORIES, open_memories)
		discard.name = "AvatarMemories"
	for slot in 3:
		var evocation: EvocationState = null
		for ev in player.evocations:
			if ev.board_number == slot + 1 and ev.assigned_mage < 0: evocation = ev
		var rect := Rect2(280 + 380 * slot, -260, 350, 235)
		if evocation == null:
			var empty := Button.new()
			empty.flat = true
			empty.position = rect.position
			empty.size = rect.size
			empty.set_meta("upright_in_portrait", true)
			cards_root.add_child(empty)
		else:
			var current = evocation
			var card = _add_card("evocations", current.evocation_id, current.get_display_name(), rect,
				func(): game.open_evocation_inspection(current, true))
			card.set_meta("evocation", current)
			card.set_meta("upright_in_portrait", true)
			var status := Label.new()
			status.text = "%s · %d/%d HP" % [["I", "II", "III"][slot], current.health - current.get_damage(), current.health]
			status.position = Vector2(8, 6)
			status.add_theme_font_size_override("font_size", 27)
			status.add_theme_color_override("font_outline_color", Color.BLACK)
			status.add_theme_constant_override("outline_size", 6)
			status.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(status)
			var damage := Control.new()
			damage.name = "EvocationDamage"
			damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
			damage.position = Vector2(12, rect.size.y - 34)
			card.add_child(damage)
			for i in current.damage_cubes.size():
				var cube = preload("res://cube.tscn").instantiate()
				var owner: int = current.damage_cubes[i]
				cube.cube_color = Color.BLACK if owner < 0 else game.players[owner].color
				damage.add_child(cube)
				cube.position = Vector2((i % 12) * 25, -(i / 12) * 25)
				cube.scale = Vector2.ONE * 1.6
	var quests: Button = game.ReferenceCardPreview.make_back("Solved Quests", Vector2(350,180))
	quests.name = "AvatarSolvedQuests"
	quests.set_meta("upright_in_portrait", true)
	quests.position = Vector2(280, 780)
	cards_root.add_child(quests)
	quests.visible = not player.completed_quests.is_empty()
	var assigned := Button.new()
	assigned.text = "Assigned Evocations"
	assigned.visible = player.evocations.any(func(ev): return ev.assigned_mage >= 0)
	assigned.set_meta("upright_in_portrait", true)
	assigned.position = Vector2(680, 780)
	assigned.size = Vector2(350, 180)
	assigned.pressed.connect(func():
		var pile: Array = player.evocations.filter(func(ev): return ev.assigned_mage >= 0).map(func(ev): return {"id":ev.evocation_id, "name":ev.get_display_name()})
		preview.show_reference_pile("evocations", pile, "Assigned Evocations", Callable()))
	cards_root.add_child(assigned)
	_add_trophies(player)
	_add_jinx_cards(player)
	_add_mage_tokens(player)
	create_damage_track()
	_update_hitboxes()
	queue_redraw()

func _add_trophies(player: PlayerState) -> void:
	if player.trophies.is_empty(): return
	var stack := Control.new()
	stack.name = "AvatarTrophies"
	stack.set_meta("upright_in_portrait", true)
	stack.position = Vector2(680, 990)
	stack.size = Vector2(350, 90)
	stack.tooltip_text = "Trophies: %d" % player.trophies.size()
	cards_root.add_child(stack)
	for i in player.trophies.size():
		var owner: int = player.trophies[i]
		var tint: Color = game.players[owner].color if owner >= 0 and owner < game.players.size() else Color.BLACK
		var token = preload("res://tabletop_style.gd").marker("trophy_token", tint, Vector2(62, 62))
		token.position = Vector2((i % 5) * 65, (i / 5) * 65)
		stack.add_child(token)

func _add_jinx_cards(player: PlayerState) -> void:
	if player.mage.jinxes.is_empty(): return
	var panel := Control.new()
	panel.name = "AvatarJinxes"
	panel.set_meta("upright_in_portrait", true)
	panel.position = Vector2(1065, 665)
	panel.size = Vector2(340, 390)
	cards_root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "Cards"
	scroll.position = Vector2.ZERO
	scroll.size = Vector2(340, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for assigned in player.mage.jinxes:
		var id: String = str(assigned.id)
		var data := ForgottenAttachments.definition("jinxes", id)
		var column := VBoxContainer.new()
		column.name = id
		grid.add_child(column)
		var card: Button = game.ReferenceCardPreview.make_card("jinxs", id, str(data.get("name", id)), Vector2(155, 237), game.open_jinx_card.bind(game.avatar.player_index, id))
		card.flat = true
		column.add_child(card)
		var progress := HBoxContainer.new()
		progress.name = "Progress"
		column.add_child(progress)
		for i in int(data.get("slots", 0)):
			var slot := Panel.new()
			slot.custom_minimum_size = Vector2(24, 24)
			progress.add_child(slot)
			if i < int(assigned.progress):
				var cube = preload("res://cube.tscn").instantiate()
				cube.cube_color = Color.BLACK
				cube.position = Vector2(5, 5)
				slot.add_child(cube)

func _add_mage_tokens(player: PlayerState) -> void:
	for kind in ["destiny", "infectio"]:
		var owners: Array = player.mage.destiny_tokens if kind == "destiny" else player.mage.infectio_tokens
		for i in owners.size():
			var token := Button.new()
			token.name = "%sToken%d" % [kind.capitalize(), i]
			token.position = Vector2(900 + (i % 3) * 58, 180 + (0 if kind == "destiny" else 64) + (i / 3) * 58)
			token.size = Vector2(52,52)
			token.set_meta("upright_in_portrait", true)
			token.tooltip_text = "%s · Player %d" % [kind.capitalize(), int(owners[i]) + 1]
			var texture: Texture2D = game.ReferenceCardPreview.card_texture("tokens", kind)
			if texture != null:
				var art := TextureRect.new()
				art.texture = texture
				art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				art.mouse_filter = Control.MOUSE_FILTER_IGNORE
				token.add_child(art)
			else: token.text = "I"
			var cube = preload("res://cube.tscn").instantiate()
			cube.cube_color = Color.BLACK if int(owners[i]) < 0 else game.players[int(owners[i])].color
			cube.position = Vector2(36,36)
			token.add_child(cube)
			cards_root.add_child(token)

func _add_card(kind: String, id: String, title: String, rect: Rect2, callback: Callable) -> Button:
	var card: Button = game.ReferenceCardPreview.make_card(kind, id, title, rect.size, callback, kind != "evocations")
	card.flat = true
	card.position = rect.position
	cards_root.add_child(card)
	return card

func _card_counter(card: Button, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(8, 8)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 7)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)

func open_memories() -> void:
	game._reference_card_preview().show_spell_pile(game.players[game.avatar.player_index].memories, "Possessed · Memories / discarded Commands")

func create_damage_track() -> void:
	if damage_track == null: return
	for slot in damage_track.get_children():
		damage_track.remove_child(slot)
		slot.queue_free()
	var owners: Array = game.players[game.avatar.player_index].mage.damage_cubes
	if game.table_shell != null:
		owners = game.table_shell.displayed_damage(game.avatar.player_index, owners)
	for i in owners.size():
		var slot := Node2D.new()
		slot.position = _health_position(i)
		damage_track.add_child(slot)
		var cube = preload("res://cube.tscn").instantiate()
		cube.name = "DamageCube"
		cube.cube_color = Color.BLACK if owners[i] < 0 else game.players[owners[i]].color
		slot.add_child(cube)
		cube.position = Vector2(-14, -14)
		cube.scale = Vector2(2, 2)
	var limit = get_node_or_null("HealthLimit")
	if limit == null:
		limit = Node2D.new()
		limit.name = "HealthLimit"
		var outline := Line2D.new()
		outline.points = PackedVector2Array([Vector2(-28,-28),Vector2(28,-28),Vector2(28,28),Vector2(-28,28),Vector2(-28,-28)])
		outline.width = 3
		outline.default_color = Color("cbb17b")
		limit.add_child(outline)
		add_child(limit)
	limit.position = _health_position(game.players[game.avatar.player_index].mage.health - 1)

func refresh_evocations() -> void: refresh()
func refresh_quests() -> void: refresh()
func refresh_spell_slots() -> void: refresh()
func refresh_action_tokens() -> void: pass
func refresh_transformation() -> void: pass

func _health_position(index: int) -> Vector2:
	return Vector2(1360 - (index / 7) * 72, 114 + (index % 7) * 80)

func reposition() -> void:
	if expanded: return
	var cell: Vector2i = game.player_cell_coords[game.avatar.player_index]
	var center: Vector2 = game.hex_to_pixel(cell)
	# Keep the Cell's interlock: board extends away from the Lodge in a 60° axis.
	rotation = snappedf((center - game.board_center).angle(), PI / 3.0)
	scale = Vector2.ONE * (game.HEX_RADIUS * sqrt(3.0) / 700.0)
	position = center - Vector2.RIGHT.rotated(rotation) * game.HEX_RADIUS - TIP.rotated(rotation) * scale.x
	table_transform = transform
	for node in game.get_children():
		if node.has_meta("owner_index") and int(node.get_meta("owner_index")) == game.avatar.player_index and node.has_meta("hex_coord"):
			node.hide()

func get_bounds() -> Rect2:
	var bounds := Rect2(table_transform.origin, Vector2.ZERO)
	for point in OUTLINE: bounds = bounds.expand(table_transform * point)
	for point in [Vector2(260, -270), Vector2(1450, 970)]: bounds = bounds.expand(table_transform * point)
	return bounds

func _process(_delta: float) -> void:
	refresh()

func _draw() -> void:
	if game == null: return
	var player: PlayerState = game.players[game.avatar.player_index]
	# Godot's SVG importer does not render SVG text. Numbers stay native text,
	# aligned with the vector recesses and behind the physical damage cubes.
	var font := ThemeDB.fallback_font
	for i in 28:
		draw_set_transform(_health_position(i), PI / 2)
		# Reuse the actual stone recess from the Power Board, without its number.
		draw_texture_rect_region(POWER_BOARD_ART, Rect2(-32, -30, 64, 60), Rect2(815, 94, 54, 53))
		draw_string(font, Vector2(-28, 10), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 56, 29, Color("d7cbaa"))
	draw_set_transform(Vector2.ZERO)
	for slot in [COMMANDS, MEMORIES]:
		draw_rect(slot, Color("151717"))
		draw_rect(slot, Color("ae9465"), false, 3)

func _text_block(rect: Rect2, text: String, font: Font) -> void:
	var lines := text.split("\n")
	for i in lines.size(): draw_string(font, rect.position + Vector2(15, rect.size.y * 0.48 + 40 * i), lines[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 30, 30, Color("ead5a5"))

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	var mouse := get_local_mouse_position()
	if expanded or game.table_shell == null: return
	if not Geometry2D.is_point_in_polygon(mouse, OUTLINE) and not Rect2(260, -270, 1190, 1240).has_point(mouse): return
	game.table_shell.open_board(game.avatar.player_index)
	get_viewport().set_input_as_handled()
