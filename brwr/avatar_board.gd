class_name AvatarBoard
extends Node2D

# Both this table view and the existing fullscreen PlayerBoard read the same
# PlayerState. No health, command count or damage is stored in visual nodes.
const TIP := Vector2(21, 382)
var OUTLINE := PackedVector2Array([Vector2(21,382),Vector2(253,33),Vector2(1441,12),Vector2(1446,687),Vector2(253,690)])
const SHEET := Rect2(698, 44, 412, 602)
const COMMANDS := Rect2(267, 52, 372, 276)
const MEMORIES := Rect2(267, 365, 372, 273)
var game
var signature := ""

func setup(owner_game) -> void:
	game = owner_game
	name = "AvatarBoard"
	var body := Polygon2D.new()
	body.texture = preload("res://assets/avatars/possessed/board_reference.png")
	body.polygon = OUTLINE
	body.uv = OUTLINE
	add_child(body)
	reposition()
	queue_redraw()

func reposition() -> void:
	var cell: Vector2i = game.player_cell_coords[game.avatar.player_index]
	var center: Vector2 = game.hex_to_pixel(cell)
	# Keep the Cell's interlock: board extends away from the Lodge in a 60° axis.
	rotation = snappedf((center - game.board_center).angle(), PI / 3.0)
	scale = Vector2.ONE * (game.HEX_RADIUS * sqrt(3.0) / 654.0)
	position = center - Vector2.RIGHT.rotated(rotation) * game.HEX_RADIUS - TIP.rotated(rotation) * scale.x
	for node in game.get_children():
		if node.has_meta("owner_index") and int(node.get_meta("owner_index")) == game.avatar.player_index and node.has_meta("hex_coord"):
			node.hide()

func get_bounds() -> Rect2:
	var bounds := Rect2(position, Vector2.ZERO)
	for point in OUTLINE: bounds = bounds.expand(transform * point)
	return bounds

func _process(_delta: float) -> void:
	if game == null: return
	var player: PlayerState = game.players[game.avatar.player_index]
	var updated := str([player.mage.damage_cubes, game.avatar.public_data(), player.completed_quests.size(), player.evocations.size()])
	if updated != signature:
		signature = updated
		queue_redraw()

func _draw() -> void:
	if game == null: return
	var player: PlayerState = game.players[game.avatar.player_index]
	var sheet := AvatarArt.texture("possessed")
	if sheet != null:
		draw_set_transform(SHEET.get_center(), -PI / 2)
		draw_texture_rect(sheet, Rect2(-Vector2(SHEET.size.y, SHEET.size.x) / 2, Vector2(SHEET.size.y, SHEET.size.x)), false)
		draw_set_transform(Vector2.ZERO)
	var font := ThemeDB.fallback_font
	for i in player.mage.damage_cubes.size():
		var x := 1391.0 - float(i / 7) * 60.0
		var y := 75.0 + float(i % 7) * 85.0
		var owner: int = player.mage.damage_cubes[i]
		draw_rect(Rect2(x - 15,y - 15,30,30), Color.BLACK if owner < 0 else game.players[owner].color)
	var public: Dictionary = game.avatar.public_data()
	for slot in [COMMANDS, MEMORIES]:
		draw_rect(slot, Color("151717"))
		draw_rect(slot, Color("ae9465"), false, 3)
	var reaction: String = str(public.reaction)
	var label := "COMMANDS · %d" % player.grimoire.size()
	if not reaction.is_empty(): label += "\n" + ("TRAP" if reaction == "suffered_damage" else "PROTECTION")
	_text_block(COMMANDS, label, font)
	if not player.memories.is_empty():
		var top: SpellCardState = player.memories.back()
		var art := AvatarArt.texture(top.id)
		if art != null:
			draw_set_transform(MEMORIES.get_center(), -PI / 2)
			draw_texture_rect(art, Rect2(-Vector2(MEMORIES.size.y, MEMORIES.size.x) / 2, Vector2(MEMORIES.size.y, MEMORIES.size.x)), false)
			draw_set_transform(Vector2.ZERO)
	else: _text_block(MEMORIES, "MEMORIES", font)
	draw_string(font, Vector2(290, 733), "%s · %d/%d Commands · %d solved Quests" % [player.player_name, game.avatar.commands_used, game.avatar.command_limit(), player.completed_quests.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("ead5a5"))

func _text_block(rect: Rect2, text: String, font: Font) -> void:
	var lines := text.split("\n")
	for i in lines.size(): draw_string(font, rect.position + Vector2(15, rect.size.y * 0.48 + 40 * i), lines[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 30, 30, Color("ead5a5"))

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
	var mouse := get_local_mouse_position()
	if SHEET.has_point(mouse):
		game._reference_card_preview().show_card("avatars", "possessed", "Possessed · Dominion", "If Possessed starts an activation in its Cell, place it in the Black Rose Room instead of revealing a Command.")
	elif MEMORIES.has_point(mouse): game.beta_hud.open_public_memories(game.avatar.player_index)
	elif COMMANDS.has_point(mouse):
		game._reference_card_preview().show_card("avatars", "command_back", "Avatar Commands", "Moon %d · %d cards\n%s · %d/%d Commands used\nCurrent reaction: %s\nThe order and faces of unrevealed Commands are hidden." % [game.current_moon, game.avatar.active_deck().size(), game.avatar.difficulty.capitalize(), game.avatar.commands_used, game.avatar.command_limit(), str(game.avatar.public_data().reaction).replace("_", " ")])
	else: return
	get_viewport().set_input_as_handled()
