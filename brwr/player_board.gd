extends Control


var player_state: PlayerState
var game = null
var player_index: int = -1

var cube_scene = preload("res://cube.tscn")


# =========================================================
# DIMENSIONI PLAYER BOARD
# =========================================================

const BOARD_SIZE = Vector2(600, 390)

# Spell Card
const SPELL_SIZE = Vector2(95, 132)

# Mage Card
const MAGE_CARD_SIZE = Vector2(215, 131)

const CARD_GAP = 12.0


# =========================================================
# DAMAGE TRACK
# =========================================================

const DAMAGE_SLOT_SIZE = 18.0
const DAMAGE_SLOT_GAP = 4.0

const DAMAGE_TRACK_POSITION = Vector2(15, 145)

# Adatta solo questo valore se visivamente il cube.tscn
# risulta troppo grande/piccolo.
const DAMAGE_CUBE_SCALE = 0.45


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
	$Background.position = Vector2.ZERO
	$Background.size = BOARD_SIZE


# =========================================================
# INFO GIOCATORE
# =========================================================

func setup_info():
	$PlayerName.position = Vector2(15, 10)
	$PlayerName.size = Vector2(150, 24)

	$MageName.position = Vector2(15, 36)
	$MageName.size = Vector2(150, 24)

	$HealthLabel.position = Vector2(15, 62)
	$HealthLabel.size = Vector2(150, 24)

	$PowerLabel.position = Vector2(15, 88)
	$PowerLabel.size = Vector2(150, 24)

	$CubeLabel.position = Vector2(15, 114)
	$CubeLabel.size = Vector2(150, 24)


# =========================================================
# MAGE CARD + SPELL
# =========================================================

func setup_main_cards():
	var cards_x = 175.0

	# -----------------------------------------------------
	# RIGA SUPERIORE
	#
	# QUICK + MAGE CARD
	# -----------------------------------------------------

	var top_y = 15.0

	setup_slot(
		$SpellSlots/QuickSpellSlot,
		Vector2(
			cards_x,
			top_y
		),
		SPELL_SIZE
	)

	setup_slot(
		$MageCardSlot,
		Vector2(
			cards_x
			+ SPELL_SIZE.x
			+ CARD_GAP,
			top_y
		),
		MAGE_CARD_SIZE
	)


	# -----------------------------------------------------
	# RIGA INFERIORE
	#
	# I + II + III
	# -----------------------------------------------------

	var bottom_y = (
		top_y
		+ SPELL_SIZE.y
		+ CARD_GAP
	)

	setup_slot(
		$SpellSlots/SpellSlotI,
		Vector2(
			cards_x,
			bottom_y
		),
		SPELL_SIZE
	)

	setup_slot(
		$SpellSlots/SpellSlotII,
		Vector2(
			cards_x
			+ SPELL_SIZE.x
			+ CARD_GAP,
			bottom_y
		),
		SPELL_SIZE
	)

	setup_slot(
		$SpellSlots/SpellSlotIII,
		Vector2(
			cards_x
			+ (
				SPELL_SIZE.x
				+ CARD_GAP
			) * 2.0,
			bottom_y
		),
		SPELL_SIZE
	)


	_configure_spell_slot($SpellSlots/QuickSpellSlot, "Q")
	_configure_spell_slot($SpellSlots/SpellSlotI, "I")
	_configure_spell_slot($SpellSlots/SpellSlotII, "II")
	_configure_spell_slot($SpellSlots/SpellSlotIII, "III")

func setup_slot(
	slot: Control,
	slot_position: Vector2,
	slot_size: Vector2
):
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
	var deck_size = Vector2(135, 52)

	$GrimoireSlot.position = Vector2(
		15,
		190
	)

	$GrimoireSlot.size = deck_size
	$GrimoireSlot.custom_minimum_size = deck_size

	$GrimoireSlot/Label.position = Vector2.ZERO
	$GrimoireSlot/Label.size = deck_size


	$MemoriesSlot.position = Vector2(
		15,
		255
	)

	$MemoriesSlot.size = deck_size
	$MemoriesSlot.custom_minimum_size = deck_size

	$MemoriesSlot/Label.position = Vector2.ZERO
	$MemoriesSlot/Label.size = deck_size


	$HandInfo.position = Vector2(
		15,
		320
	)

	$HandInfo.size = Vector2(
		135,
		25
	)


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
		label.visible = true
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
			token.position = Vector2(520, 15 + i * 60)
			token.size = Vector2(54, 54)
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
			button.position = Vector2(175 + i * 137, 349)
			button.size = Vector2(130, 30)
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
			heading.position = Vector2(12, 168) if section == "revealed" else Vector2(505, 138)
			heading.add_theme_font_size_override("font_size", 12)
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(heading)
		var strip = get_node_or_null("Quest_" + section)
		if strip == null:
			strip = ScrollContainer.new()
			strip.name = "Quest_" + section
			strip.position = Vector2(12, 190) if section == "revealed" else Vector2(505, 159)
			strip.size = Vector2(145, 155) if section == "revealed" else Vector2(88, 155)
			add_child(strip)
		for child in strip.get_children():
			child.free()
		var row := HBoxContainer.new()
		strip.add_child(row)
		for data in game.get_player_quest_cards(player_index, section):
			var card = game.ReferenceCardPreview.make_card("quests", data.id, data.name,
				Vector2(80, 112), game.open_quest_card.bind(data.quest))
			row.add_child(card)
			var quest: QuestState = data.quest
			if quest.get_cube_slots() > 0:
				var track := HBoxContainer.new()
				track.name = "QuestProgress"
				track.position = Vector2(5, 48)
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
		counter.position = Vector2(15, 360)
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
			1.0
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


		# Il cube.tscn è un Node2D:
		# lo centriamo nello slot.
		cube.position = Vector2(
			DAMAGE_SLOT_SIZE / 2.0,
			DAMAGE_SLOT_SIZE / 2.0
		)

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
