extends Control


var player_state: PlayerState
var game = null
var player_index: int = -1

var cube_scene = preload("res://cube.tscn")


# =========================================================
# DIMENSIONI PLAYER BOARD
# =========================================================

const BOARD_SIZE = Vector2(900, 730)
const SHEET_VARIANTS = {
	Color.RED: "mage_sheet_red.png",
	Color.BLUE: "mage_sheet_blue.png",
	Color.GREEN: "mage_sheet_green.png",
	Color.PURPLE: "mage_sheet_purple.png",
	Color.YELLOW: "mage_sheet_yellow.png",
	Color.WHITE: "mage_sheet.png",
}

# Spell Card
const SPELL_SIZE = Vector2(150, 200)

# Mage Card
const MAGE_CARD_SIZE = Vector2(330, 190)

const CARD_GAP = 12.0


# =========================================================
# DAMAGE TRACK
# =========================================================

const DAMAGE_SLOT_SIZE = 24.0
const DAMAGE_SLOT_GAP = 18.0

const DAMAGE_TRACK_POSITION = Vector2(204, 61)

# Adatta solo questo valore se visivamente il cube.tscn
# risulta troppo grande/piccolo.
const DAMAGE_CUBE_SCALE = DAMAGE_SLOT_SIZE / 14.0


# =========================================================
# READY
# =========================================================

func _ready():
	setup_layout()


# =========================================================
# PLAYER SETUP
# =========================================================

func setup(
	player: PlayerState,
	game_node = null,
	index: int = -1
):
	player_state = player
	game = game_node
	player_index = index if index >= 0 else player.player_index

	create_damage_track()
	refresh()


func refresh():
	if player_state == null:
		return
	refresh_sheet_art()

	$PlayerName.text = player_state.player_name

	if player_state.mage.mage_id == "":
		$MageName.text = "Mage: -"
	else:
		$MageName.text = "Mage: " + player_state.mage.mage_id

	$HealthLabel.text = (
		"HP: "
		+ str(player_state.mage.get_remaining_health())
		+ "/"
		+ str(player_state.mage.health)
	)

	$PowerLabel.text = (
		"Power: "
		+ str(player_state.power)
	)

	$CubeLabel.text = (
		"Cubes: "
		+ str(player_state.available_cubes)
	)

	$HandInfo.text = (
		"Hand: "
		+ str(player_state.get_hand_size())
	)

	refresh_spell_slots()
	refresh_damage_track()
	refresh_quests()
	refresh_action_tokens()
	refresh_evocations()
	refresh_mage_card()
	$GrimoireSlot/Label.text = "GRIMOIRE\n%d" % player_state.grimoire.size()
	$MemoriesSlot/Label.text = "MEMORIES\n%d" % player_state.memories.size()


# =========================================================
# LAYOUT GENERALE
# =========================================================

func setup_layout():
	size = BOARD_SIZE
	custom_minimum_size = BOARD_SIZE

	setup_background()
	setup_info()
	setup_main_cards()
	setup_deck_slots()


func setup_background():
	$Background.hide()
	if get_node_or_null("SheetArt") == null:
		var art := TextureRect.new()
		art.name = "SheetArt"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.texture = preload("res://assets/player_boards/mage_sheet.png")
		art.position = Vector2(150, 40)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.size = Vector2(600, 500)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		move_child(art, 0)
	refresh_sheet_art()


func refresh_sheet_art() -> void:
	var art := get_node_or_null("SheetArt") as TextureRect
	if art == null or player_state == null:
		return
	var filename: String = SHEET_VARIANTS.get(player_state.color, "mage_sheet.png")
	art.texture = load("res://assets/player_boards/" + filename)


func setup_info():
	var positions := [Vector2(150, 8), Vector2(380, 104), Vector2(290, 8), Vector2(420, 8), Vector2(550, 8)]
	var nodes := [$PlayerName, $MageName, $HealthLabel, $PowerLabel, $CubeLabel]
	for i in range(nodes.size()):
		nodes[i].position = positions[i]
		nodes[i].size = Vector2(150, 24)
		nodes[i].mouse_filter = Control.MOUSE_FILTER_IGNORE
		nodes[i].z_index = 3
	$MageName.visible = false


func setup_main_cards():
	setup_slot($SpellSlots/QuickSpellSlot, Vector2(203, 94), SPELL_SIZE)
	setup_slot($MageCardSlot, Vector2(368, 94), MAGE_CARD_SIZE)
	setup_slot($SpellSlots/SpellSlotI, Vector2(203, 304), SPELL_SIZE)
	setup_slot($SpellSlots/SpellSlotII, Vector2(372, 304), SPELL_SIZE)
	setup_slot($SpellSlots/SpellSlotIII, Vector2(540, 304), SPELL_SIZE)
	_configure_spell_slot($SpellSlots/QuickSpellSlot, "Q")
	_configure_spell_slot($SpellSlots/SpellSlotI, "I")
	_configure_spell_slot($SpellSlots/SpellSlotII, "II")
	_configure_spell_slot($SpellSlots/SpellSlotIII, "III")


func setup_slot(
	slot: Control,
	slot_position: Vector2,
	slot_size: Vector2
):
	slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.position = slot_position
	slot.size = slot_size
	slot.custom_minimum_size = slot_size

	var label = slot.get_node_or_null("Label")

	if label != null:
		label.position = Vector2.ZERO
		label.size = slot_size

		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER
		)

		label.vertical_alignment = (
			VERTICAL_ALIGNMENT_CENTER
		)


# =========================================================
# GRIMOIRE / MEMORIES / HAND
# =========================================================

func setup_deck_slots():
	setup_slot($GrimoireSlot, Vector2(12, 320), Vector2(126, 180))
	setup_slot($MemoriesSlot, Vector2(762, 320), Vector2(126, 180))
	for deck in [$GrimoireSlot, $MemoriesSlot]:
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color(0.035, 0.035, 0.045)
		frame.border_color = Color(0.5, 0.48, 0.45)
		frame.set_border_width_all(1)
		frame.set_corner_radius_all(6)
		deck.add_theme_stylebox_override("panel", frame)
	$HandInfo.position = Vector2(690, 8)
	$HandInfo.size = Vector2(110, 25)


func _configure_spell_slot(slot: Control, slot_id: String) -> void:
	if slot.get_node_or_null("CardBack") == null:
		var back := ColorRect.new()
		back.name = "CardBack"
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.color = Color(0.055, 0.055, 0.07, 1.0)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.visible = false
		slot.add_child(back)
		slot.move_child(back, 0)

	if slot.get_node_or_null("CardArt") == null:
		var art := TextureRect.new()
		art.name = "CardArt"
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.visible = false
		slot.add_child(art)

	if slot.get_node_or_null("CardClickButton") == null:
		var button := Button.new()
		button.name = "CardClickButton"
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		button.text = ""
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(
			Callable(self, "_on_spell_slot_pressed").bind(slot_id)
		)
		slot.add_child(button)


func refresh_spell_slots() -> void:
	if player_state == null:
		return

	_render_spell_slot($SpellSlots/QuickSpellSlot, "Q", "QUICK")
	_render_spell_slot($SpellSlots/SpellSlotI, "I", "I")
	_render_spell_slot($SpellSlots/SpellSlotII, "II", "II")
	_render_spell_slot($SpellSlots/SpellSlotIII, "III", "III")


func _render_spell_slot(
	slot: Control,
	slot_id: String,
	empty_label: String
) -> void:
	_configure_spell_slot(slot, slot_id)

	var label: Label = slot.get_node_or_null("Label")
	var back: ColorRect = slot.get_node_or_null("CardBack")
	var art: TextureRect = slot.get_node_or_null("CardArt")
	var button: Button = slot.get_node_or_null("CardClickButton")

	if label == null or back == null or art == null or button == null:
		return

	var data: Dictionary = {}
	if game != null:
		data = game.get_player_board_spell_slot_data(player_index, slot_id)
	var marker = slot.get_node_or_null("SpellMarker")
	if marker == null:
		marker = Label.new()
		marker.name = "SpellMarker"
		marker.position = Vector2(2, 3)
		marker.z_index = 2
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_theme_font_size_override("font_size", 11)
		marker.add_theme_color_override("font_outline_color", Color.BLACK)
		marker.add_theme_constant_override("outline_size", 6)
		var badge := StyleBoxFlat.new()
		badge.bg_color = Color(0.25, 0.13, 0.38, 0.95)
		badge.set_corner_radius_all(5)
		badge.content_margin_left = 4
		badge.content_margin_right = 4
		marker.add_theme_stylebox_override("normal", badge)
		slot.add_child(marker)
	marker.text = str(data.get("marker", ""))
	marker.visible = not marker.text.is_empty()

	if data.is_empty():
		back.visible = false
		art.visible = false
		art.texture = null
		label.visible = false
		label.text = empty_label
		button.disabled = true
		button.tooltip_text = ""
		return

	var public_card: bool = bool(data.get("public", false))

	if public_card:
		var texture: Texture2D = SpellArtResolver.get_texture(
			str(data.get("id", "")),
			str(data.get("school_id", ""))
		)

		back.visible = false

		if texture != null:
			art.texture = texture
			art.visible = true
			label.visible = false
		else:
			art.texture = null
			art.visible = false
			label.visible = true
			label.text = str(data.get("name", "Spell"))

		button.disabled = false
		button.tooltip_text = (
			str(data.get("name", "Spell")) + " — click to inspect"
		)
		return

	back.visible = true
	art.texture = null
	art.visible = false
	label.visible = true
	label.text = empty_label + "\nSET"

	var can_inspect: bool = bool(data.get("can_inspect", false))
	button.disabled = not can_inspect
	button.tooltip_text = (
		"Click to inspect your prepared Spell"
		if can_inspect
		else "Prepared Spell — hidden"
	)


func _on_spell_slot_pressed(slot_id: String) -> void:
	if game == null:
		return
	game.activate_player_board_spell(player_index, slot_id, Input.is_key_pressed(KEY_SHIFT))


func refresh_action_tokens() -> void:
	if game == null or player_state == null:
		return
	for i in range(PlayerState.MAX_PHYSICAL_ACTIONS):
		var token = get_node_or_null("PhysicalAction" + str(i))
		if token == null:
			token = Button.new()
			token.name = "PhysicalAction" + str(i)
			token.position = Vector2(382 + i * 55, 229)
			token.size = Vector2(46, 46)
			token.add_theme_font_size_override("font_size", 36)
			token.pressed.connect(game.open_player_board_action.bind(player_index, "physical"))
			add_child(token)
		var available: bool = i < player_state.available_physical_actions
		token.text = "+" if available else "×"
		token.tooltip_text = "Physical action: Explore / Fight / Command" if available else "Physical action exhausted"
		token.disabled = not available or game.get_player_board_action_options(player_index, "physical").is_empty()
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.04, 0.05, 0.07)
			style.border_color = get_damage_cube_color(player_index)
			style.set_border_width_all(5)
			style.set_corner_radius_all(10)
			if state == "hover":
				style.bg_color = Color(0.18, 0.2, 0.25)
			token.add_theme_stylebox_override(state, style)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			token.add_theme_color_override(state, Color.WHITE if available else Color(1, 0.12, 0.12))
	for i in range(3):
		var category: String = ["momentum", "quests", "finish"][i]
		var button = get_node_or_null("BoardAction_" + category)
		if button == null:
			button = Button.new()
			button.name = "BoardAction_" + category
			button.text = ["Momentum", "Resolve Quest", "End activation"][i]
			button.position = Vector2(203 + i * 169, 695)
			button.size = Vector2(150, 30)
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(game.open_player_board_action.bind(player_index, category))
			add_child(button)
		button.visible = not game.get_player_board_action_request(player_index).is_empty()
		button.disabled = game.get_player_board_action_options(player_index, category).is_empty()
	for slot_id in ["Q", "I", "II", "III"]:
		var slot_path: String = "QuickSpellSlot" if slot_id == "Q" else "SpellSlot" + slot_id
		var button = get_node_or_null("SpellSlots/" + slot_path + "/CardClickButton")
		if button != null and game.get_player_board_cast_token(player_index, slot_id) != "":
			button.tooltip_text = "Click to cast · Shift-click to inspect"


func refresh_quests() -> void:
	if game == null:
		return
	for section in ["revealed", "completed"]:
		var heading = get_node_or_null("QuestHeading_" + section)
		if heading == null:
			heading = Label.new()
			heading.name = "QuestHeading_" + section
			heading.text = "QUESTS" if section == "revealed" else "COMPLETED"
			heading.position = Vector2(12, 40) if section == "revealed" else Vector2(762, 40)
			heading.add_theme_font_size_override("font_size", 12)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(heading)
		var strip = get_node_or_null("Quest_" + section)
		if strip == null:
			strip = ScrollContainer.new()
			strip.name = "Quest_" + section
			strip.position = Vector2(12, 65) if section == "revealed" else Vector2(762, 65)
			strip.size = Vector2(126, 235)
			add_child(strip)
		for child in strip.get_children():
			strip.remove_child(child)
			child.queue_free()
		var row := VBoxContainer.new()
		strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		strip.add_child(row)
		for data in game.get_player_board_quest_cards(player_index, section):
			var card: Button
			if not data.get("can_inspect", false):
				card = Button.new()
				card.custom_minimum_size = Vector2(112, 154)
				card.text = "QUEST\nSET"
				card.disabled = true
			else:
				card = game.ReferenceCardPreview.make_card("quests", data.id, data.name,
					Vector2(112, 154), game.open_quest_card.bind(data.quest))
			row.add_child(card)
			var quest: QuestState = data.get("quest")
			if quest != null and quest.get_cube_slots() > 0:
				var track := HBoxContainer.new()
				track.name = "QuestProgress"
				track.position = Vector2(12, 70)
				track.mouse_filter = Control.MOUSE_FILTER_IGNORE
				track.add_theme_constant_override("separation", 3)
				card.add_child(track)
				for i in range(quest.get_cube_slots()):
					var cube := ColorRect.new()
					cube.custom_minimum_size = Vector2(12, 12)
					cube.color = get_damage_cube_color(player_index) if i < quest.progress else Color(0.12, 0.12, 0.12, 0.85)
					cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
					track.add_child(cube)
	var counter = get_node_or_null("SolvedQuestCount")
	if counter == null:
		counter = Label.new()
		counter.name = "SolvedQuestCount"
		counter.position = Vector2(762, 302)
		counter.add_theme_font_size_override("font_size", 13)
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(counter)
	var solved: int = 0
	for quest in player_state.completed_quests:
		if quest.solved:
			solved += 1
	counter.text = "Solved Quests: " + str(solved)


func create_damage_track():
	if player_state == null:
		return

	# Se per qualche motivo setup() venisse richiamato,
	# eliminiamo immediatamente il vecchio track.
	var old_track = get_node_or_null("DamageTrack")

	if old_track != null:
		old_track.free()


	var track = Control.new()

	track.name = "DamageTrack"
	track.position = DAMAGE_TRACK_POSITION

	add_child(track)


	# Una casella per ogni punto Health del Mage.
	for i in range(player_state.mage.health):
		var slot = ColorRect.new()

		slot.name = (
			"DamageSlot_"
			+ str(i)
		)

		slot.position = Vector2(
			i
			* (
				DAMAGE_SLOT_SIZE
				+ DAMAGE_SLOT_GAP
			),
			0
		)

		slot.size = Vector2(
			DAMAGE_SLOT_SIZE,
			DAMAGE_SLOT_SIZE
		)

		# Fondo dello slot vuoto.
		slot.color = Color(
			0.20,
			0.20,
			0.20,
			0.0
		)

		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		track.add_child(slot)


func refresh_damage_track():
	if player_state == null:
		return

	var track = get_node_or_null("DamageTrack")

	if track == null:
		return


	# -----------------------------------------------------
	# Rimuove i cubi grafici precedenti
	# -----------------------------------------------------

	for slot in track.get_children():
		var old_cube = slot.get_node_or_null(
			"DamageCube"
		)

		if old_cube != null:
			old_cube.free()


	# -----------------------------------------------------
	# Legge lo stato vero dal MageState
	# -----------------------------------------------------

	var damage_cubes = (
		player_state.mage.damage_cubes
	)


	# -----------------------------------------------------
	# Disegna i cubi
	# -----------------------------------------------------

	for i in range(damage_cubes.size()):
		if i >= track.get_child_count():
			break

		var owner_id = damage_cubes[i]

		var slot = track.get_child(i)

		var cube = cube_scene.instantiate()

		cube.name = "DamageCube"

		cube.cube_color = (
			get_damage_cube_color(owner_id)
		)

		slot.add_child(cube)


		# Cube is a Control drawn from its top-left corner.
		cube.position = Vector2.ZERO

		cube.scale = Vector2(
			DAMAGE_CUBE_SCALE,
			DAMAGE_CUBE_SCALE
		)


# =========================================================
# COLORI DAMAGE CUBES
# =========================================================

func get_damage_cube_color(
	owner_id: int
) -> Color:

	# Black Rose
	if owner_id == -1:
		return Color.BLACK
	if game != null and owner_id >= 0 and owner_id < game.players.size():
		return game.players[owner_id].color


	var colors = [
		Color.RED,
		Color.BLUE,
		Color.GREEN,
		Color.PURPLE,
		Color.YELLOW,
		Color.WHITE
	]


	if owner_id >= 0 and owner_id < colors.size():
		return colors[owner_id]


	return Color.GRAY

func refresh_mage_card() -> void:
	var art = $MageCardSlot.get_node_or_null("MageArt")
	if art == null:
		art = TextureRect.new()
		art.name = "MageArt"
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$MageCardSlot.add_child(art)
	art.texture = game.ReferenceCardPreview.card_texture("mages", player_state.mage.mage_id) if game != null else null
	# Existing user-supplied contact sheet: use its original pixels without modifying it.
	if art.texture == null and player_state.mage.mage_id == "rikkart":
		var atlas := AtlasTexture.new()
		atlas.atlas = preload("res://assets/mages/screen_3.png")
		atlas.region = Rect2(1100, 14, 396, 249)
		art.texture = atlas
	$MageCardSlot/Label.visible = art.texture == null
	$MageCardSlot/Label.text = player_state.mage.mage_id.capitalize() + "\nStrength %d · Movement %d" % [player_state.mage.strength, player_state.mage.speed]
	var trophies = get_node_or_null("Trophies")
	if trophies == null:
		trophies = Label.new()
		trophies.name = "Trophies"
		trophies.position = Vector2(610, 248)
		trophies.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(trophies)
	trophies.text = "Trophies: %d" % player_state.trophies.size()


func refresh_evocations() -> void:
	if game == null or player_state == null:
		return
	var row = get_node_or_null("EvocationCards")
	if row == null:
		row = Control.new()
		row.name = "EvocationCards"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for evocation in player_state.evocations:
		if not game.is_evocation_in_play(evocation):
			continue
		var card = game.ReferenceCardPreview.make_card("evocations", evocation.evocation_id,
			evocation.get_display_name(), Vector2(164, 110), game.open_evocation_inspection.bind(evocation))
		card.name = "EvocationSlot" + str(evocation.board_number)
		card.position = Vector2(196 + (evocation.board_number - 1) * 169, 552)
		card.set_meta("evocation", evocation)
		row.add_child(card)
		var damage := HBoxContainer.new()
		damage.name = "EvocationDamage"
		damage.position = Vector2(4, 4)
		damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		damage.add_theme_constant_override("separation", 1)
		card.add_child(damage)
		for owner_id in evocation.damage_cubes:
			var cube = cube_scene.instantiate()
			cube.cube_color = get_damage_cube_color(owner_id)
			damage.add_child(cube)
		var label := Label.new()
		label.position = Vector2(4, 111)
		label.text = "#%d · HP %d/%d · P%d" % [evocation.board_number, evocation.get_remaining_health(), evocation.health, game.get_evocation_controller_id(evocation) + 1]
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(label)
