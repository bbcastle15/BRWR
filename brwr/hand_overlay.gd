class_name HandOverlay
extends Control


signal preparation_confirmed(payload: Dictionary)
signal study_confirmed(indices: Array)
signal overlay_closed
signal confirmation_changed(button: Button)


const MODE_BROWSE := "browse"
const MODE_PREPARATION := "preparation"
const MODE_STUDY := "study"
var study_selection: Array[int] = []
var study_confirm_button: Button

const CARD_ASPECT := 630.0 / 880.0
const CARD_MAX_WIDTH := 630.0
const CARD_GAP := 18
const VISIBLE_CARD_LIMIT := 6

# First try the common deterministic paths. If none exists, the script performs
# one cached recursive search for <spell_id>.png under res://.
const CARD_ART_ROOTS: Array[String] = [
	"res://assets/cards/spells",
	"res://assets/cards",
	"res://assets/spell_cards",
	"res://assets/spells",
	"res://cards/spells",
	"res://cards",
	"res://spell_cards",
	"res://art/cards",
	"res://art/spells",
	"res://images/cards",
	"res://images/spells"
]


var game = null

var mode: String = MODE_BROWSE
var owner_player_index: int = -1
var current_request: Dictionary = {}
var cards: Array = []

var selected_hand_index: int = -1
var selected_dark: bool = false

var ready_hand_indices: Array[int] = []
var ready_dark_sides: Array[bool] = []
var quick_hand_index: int = -1
var quick_dark_side: bool = false

var texture_cache: Dictionary = {}


var dim_background: ColorRect
var main_panel: PanelContainer

var title_label: Label
var instruction_label: Label
var count_label: Label
var close_button: Button

var card_scroll: ScrollContainer
var card_row: GridContainer

var prep_controls: VBoxContainer
var selection_label: Label
var slots_label: Label

var light_button: Button
var dark_button: Button
var ready_button: Button
var quick_button: Button
var unassign_button: Button
var clear_button: Button
var confirm_button: Button

var feedback_label: Label
var tabs: TabBar
var quest_scroll: ScrollContainer
var quest_columns: HBoxContainer
var quest_signature := ""
var cards_heading := ""
var cards_instructions := ""


func setup(game_node) -> void:
	game = game_node

	name = "HandOverlay"
	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	visible = false

	_build_ui()


func _build_ui() -> void:
	dim_background = ColorRect.new()
	dim_background.color = Color(0.0, 0.0, 0.0, 0.78)
	dim_background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	dim_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim_background)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	outer_margin.add_theme_constant_override("margin_left", 12)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_top", 132)
	outer_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(outer_margin)

	main_panel = PanelContainer.new()
	main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	main_panel.add_theme_stylebox_override("panel", preload("res://tabletop_style.gd").panel())

	outer_margin.add_child(main_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 20)
	panel_margin.add_theme_constant_override("margin_right", 20)
	panel_margin.add_theme_constant_override("margin_top", 16)
	panel_margin.add_theme_constant_override("margin_bottom", 16)
	main_panel.add_child(panel_margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	panel_margin.add_child(root)

	# -----------------------------------------------------
	# HEADER
	# -----------------------------------------------------

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	title_label = Label.new()
	title_label.text = "HAND"
	title_label.add_theme_font_size_override("font_size", 24)
	header_text.add_child(title_label)

	instruction_label = Label.new()
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction_label.modulate = Color(0.86, 0.86, 0.86)
	header_text.add_child(instruction_label)

	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 16)
	header.add_child(count_label)

	close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 42)
	close_button.pressed.connect(
		_on_close_pressed
	)
	header.add_child(close_button)

	root.add_child(HSeparator.new())

	# -----------------------------------------------------
	# LARGE CARD STRIP
	# -----------------------------------------------------
	tabs = TabBar.new()
	tabs.add_tab("Cards")
	tabs.add_tab("Quests")
	tabs.tab_changed.connect(_change_tab)
	root.add_child(tabs)

	var hand_body := HBoxContainer.new()
	hand_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_body.add_theme_constant_override("separation", 18)
	root.add_child(hand_body)
	card_scroll = ScrollContainer.new()
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.resized.connect(func(): call_deferred("_layout_cards"))
	hand_body.add_child(card_scroll)

	var card_margin := MarginContainer.new()
	card_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_margin.add_theme_constant_override("margin_left", 8)
	card_margin.add_theme_constant_override("margin_right", 8)
	card_margin.add_theme_constant_override("margin_top", 6)
	card_margin.add_theme_constant_override("margin_bottom", 6)
	card_scroll.add_child(card_margin)

	var card_center := CenterContainer.new()
	card_margin.add_child(card_center)
	card_row = GridContainer.new()
	card_row.columns = 4
	card_row.add_theme_constant_override("h_separation", CARD_GAP)
	card_row.add_theme_constant_override("v_separation", 12)
	card_center.add_child(card_row)
	quest_scroll = ScrollContainer.new()
	quest_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_body.add_child(quest_scroll)
	quest_columns = HBoxContainer.new()
	quest_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_columns.add_theme_constant_override("separation", 18)
	quest_scroll.add_child(quest_columns)
	quest_scroll.hide()

	root.add_child(HSeparator.new())

	# -----------------------------------------------------
	# PREPARATION CONTROLS
	# -----------------------------------------------------

	prep_controls = VBoxContainer.new()
	prep_controls.add_theme_constant_override("separation", 8)
	root.add_child(prep_controls)

	selection_label = Label.new()
	selection_label.add_theme_font_size_override("font_size", 17)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prep_controls.add_child(selection_label)

	slots_label = Label.new()
	slots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slots_label.add_theme_font_size_override("font_size", 15)
	prep_controls.add_child(slots_label)

	var choice_row := HBoxContainer.new()
	choice_row.add_theme_constant_override("separation", 8)
	prep_controls.add_child(choice_row)

	var side_label := Label.new()
	side_label.text = "Side:"
	side_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	choice_row.add_child(side_label)

	light_button = Button.new()
	light_button.text = "Light"
	light_button.toggle_mode = true
	light_button.custom_minimum_size = Vector2(90, 40)
	light_button.pressed.connect(
		Callable(self, "_set_selected_side").bind(false)
	)
	choice_row.add_child(light_button)

	dark_button = Button.new()
	dark_button.text = "Dark"
	dark_button.toggle_mode = true
	dark_button.custom_minimum_size = Vector2(90, 40)
	dark_button.pressed.connect(
		Callable(self, "_set_selected_side").bind(true)
	)
	choice_row.add_child(dark_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_row.add_child(spacer)

	ready_button = Button.new()
	ready_button.text = "Ready"
	ready_button.custom_minimum_size = Vector2(130, 40)
	ready_button.pressed.connect(
		_assign_selected_numbered
	)
	choice_row.add_child(ready_button)

	quick_button = Button.new()
	quick_button.text = "Quick"
	quick_button.custom_minimum_size = Vector2(120, 40)
	quick_button.pressed.connect(
		_assign_selected_quick
	)
	choice_row.add_child(quick_button)

	unassign_button = Button.new()
	unassign_button.text = "Unassign"
	unassign_button.custom_minimum_size = Vector2(110, 40)
	unassign_button.pressed.connect(
		_unassign_selected
	)
	choice_row.add_child(unassign_button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	prep_controls.add_child(action_row)

	feedback_label = Label.new()
	feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.modulate = Color(0.90, 0.82, 0.55)
	action_row.add_child(feedback_label)

	clear_button = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(100, 42)
	clear_button.pressed.connect(
		_clear_preparation
	)
	action_row.add_child(clear_button)

	confirm_button = Button.new()
	confirm_button.text = "Confirm"
	confirm_button.custom_minimum_size = Vector2(130, 42)
	confirm_button.pressed.connect(
		_confirm_preparation
	)
	action_row.add_child(confirm_button)
	study_confirm_button = Button.new()
	study_confirm_button.text = "Keep selected cards"
	study_confirm_button.pressed.connect(func():
		if study_selection.size() == 2:
			study_confirmed.emit(study_selection.duplicate()))
	study_confirm_button.hide()
	header.add_child(study_confirm_button)
	header.move_child(study_confirm_button, header.get_child_count() - 2)


func open_study(request: Dictionary) -> void:
	mode = MODE_STUDY
	current_request = request.duplicate(true)
	owner_player_index = int(request.get("player_index", -1))
	cards = request.get("cards", []).duplicate(true)
	for card in cards:
		card["hand_index"] = card.get("draw_index", -1)
	study_selection.clear()
	ready_hand_indices.clear()
	quick_hand_index = -1
	selected_hand_index = -1
	title_label.text = "PLAYER %d — STUDY" % (owner_player_index + 1)
	instruction_label.text = "Choose two cards to keep. Click a selected card to deselect it."
	close_button.disabled = false
	close_button.text = "Hide"
	prep_controls.hide()
	study_confirm_button.show()
	visible = true
	move_to_front()
	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func open_preparation(
	request: Dictionary
) -> void:
	mode = MODE_PREPARATION
	study_confirm_button.hide()
	current_request = request.duplicate(true)
	owner_player_index = int(
		current_request.get(
			"player_index",
			-1
		)
	)

	cards = current_request.get(
		"hand",
		[]
	).duplicate(true)

	selected_hand_index = -1
	selected_dark = false

	ready_hand_indices.clear()
	ready_dark_sides.clear()
	quick_hand_index = -1
	quick_dark_side = false

	title_label.text = (
		"PLAYER "
		+ str(owner_player_index + 1)
		+ " — PREPARATION"
	)

	instruction_label.text = (
		"Select a card, choose Light or Dark, then assign it to the "
		+ "next numbered Spell Slot or to Quick. "
		+ "Prepare 2–4 Spells total, with at most 3 numbered Spells."
	)

	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Hide"

	prep_controls.visible = true
	feedback_label.text = ""

	visible = true
	move_to_front()

	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func open_browse(
	player_index: int
) -> void:
	if game == null:
		return

	if player_index < 0 \
	or player_index >= game.players.size():
		return
	if player_index != game.get_ui_viewer_player_index():
		return

	mode = MODE_BROWSE
	study_confirm_button.hide()
	current_request.clear()
	owner_player_index = player_index

	var state: Dictionary = game.get_beta_game_state(
		player_index
	)

	var player_states: Array = state.get(
		"players",
		[]
	)

	if player_index >= player_states.size():
		return

	var player_data: Dictionary = player_states[
		player_index
	]

	cards.clear()

	var source_hand: Array = player_data.get(
		"hand",
		[]
	)

	for i in range(source_hand.size()):
		var card_value = source_hand[i]

		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value.duplicate(
			true
		)

		card["hand_index"] = i
		cards.append(card)

	selected_hand_index = -1
	selected_dark = false

	title_label.text = (
		"PLAYER "
		+ str(player_index + 1)
		+ " — HAND"
	)

	instruction_label.text = (
		"Browse your Hand. Press H, Esc, or Close to return to the Lodge."
	)

	close_button.visible = true
	close_button.disabled = false
	close_button.text = "Close"

	prep_controls.visible = false

	visible = true
	move_to_front()

	_render_cards()
	_update_controls()
	_select_cards_tab(true)


func _select_cards_tab(refresh_heading: bool = false) -> void:
	if refresh_heading:
		cards_heading = title_label.text
		cards_instructions = instruction_label.text
	tabs.set_current_tab(0)
	_change_tab(0)


func _change_tab(index: int) -> void:
	card_scroll.visible = index == 0
	quest_scroll.visible = index == 1
	prep_controls.visible = index == 0 and mode == MODE_PREPARATION
	if index == 1:
		title_label.text = "PLAYER %d — QUESTS" % (owner_player_index + 1)
		instruction_label.text = "Complete the Task of an Active Quest, then resolve its Effects during your Activation. Solved Quests award Power."
		count_label.text = ""
		_render_quests()
	else:
		title_label.text = cards_heading
		instruction_label.text = cards_instructions
		count_label.text = "%d cards" % cards.size()
		call_deferred("_layout_cards")
	# A preparation/study draft belongs to the Cards tab, and is preserved.
	if mode in [MODE_PREPARATION, MODE_STUDY]:
		_update_controls()


func _process(_delta: float) -> void:
	if not visible or game == null:
		return
	if owner_player_index != game.get_ui_viewer_player_index():
		close_overlay(true)
		return
	if tabs.current_tab == 1:
		var signature := str(game.get_player_board_action_options(owner_player_index, "quests"))
		for data in game.get_player_quest_cards(owner_player_index, "active") + game.get_player_quest_cards(owner_player_index, "completed") + game.get_player_quest_cards(owner_player_index, "solved"):
			var quest: QuestState = data.quest
			signature += str([quest.get_instance_id(), quest.revealed, quest.progress, quest.completed, quest.solved])
		if signature != quest_signature:
			quest_signature = signature
			_render_quests()


func _render_quests() -> void:
	for child in quest_columns.get_children():
		quest_columns.remove_child(child)
		child.queue_free()
	for section in ["active", "completed", "solved"]:
		var column := VBoxContainer.new()
		column.name = section.capitalize()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		column.add_theme_constant_override("separation", 12)
		quest_columns.add_child(column)
		var entries: Array = game.get_player_quest_cards(owner_player_index, section)
		var heading := Label.new()
		heading.text = "%s · %d" % [section.capitalize(), entries.size()]
		heading.add_theme_font_size_override("font_size", 21)
		heading.add_theme_color_override("font_color", Color("cbb178"))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		if entries.is_empty():
			var empty := Label.new()
			empty.text = "—"
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(empty)
		for data in entries:
			var quest: QuestState = data.quest
			var center := CenterContainer.new()
			column.add_child(center)
			var width := clampf((main_panel.size.x - 160) / 3.0, 140, 260)
			var card_size := Vector2(width, width * 1.42)
			var card: Button = game.ReferenceCardPreview.make_card("quests", quest.get_id(), quest.get_name(), card_size, game.open_quest_card.bind(quest))
			card.set_meta("choice_quest", quest)
			center.add_child(card)
			# Solved cards are face down on the physical table, but their now-public
			# identity can still be consulted through the same inspector.
			if section == "solved":
				for art in card.get_children():
					art.hide()
				var back := TextureRect.new()
				back.texture = preload("res://assets/tabletop/card_back.png")
				back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				back.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(back)
				back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				var caption := Label.new()
				caption.text = quest.get_name() + "\nSolved · %d Power" % quest.get_power_reward()
				caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				caption.add_theme_color_override("font_outline_color", Color.BLACK)
				caption.add_theme_constant_override("outline_size", 6)
				caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(caption)
			elif quest.get_cube_slots() > 0:
				var track := HBoxContainer.new()
				track.name = "QuestProgress"
				track.mouse_filter = Control.MOUSE_FILTER_IGNORE
				track.add_theme_constant_override("separation", 5)
				var width_value := quest.get_cube_slots() * 19.0 - 5.0
				track.position = Vector2((card_size.x - width_value) * 0.5, card_size.y * 0.5 - 7)
				card.add_child(track)
				for i in quest.get_cube_slots():
					var cube = preload("res://cube.tscn").instantiate()
					cube.cube_color = game.players[owner_player_index].color if i < quest.progress else Color("222728")
					track.add_child(cube)
			var status := Label.new()
			status.text = "Revealed" if quest.revealed else "Private"
			if section != "active": status.text = section.capitalize()
			status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(status)
			if section == "completed":
				var solve := Button.new()
				solve.text = "Resolve Quest"
				solve.disabled = true
				for option in game.get_player_board_action_options(owner_player_index, "quests"):
					var index: int = int(option.get("descriptor", {}).get("quest_index", -1))
					if index >= 0 and index < game.players[owner_player_index].completed_quests.size() and game.players[owner_player_index].completed_quests[index] == quest:
						solve.disabled = false
						solve.pressed.connect(_resolve_quest.bind(str(option.token)), CONNECT_DEFERRED)
				column.add_child(solve)


func _resolve_quest(token: String) -> void:
	if owner_player_index != game.get_ui_viewer_player_index():
		return
	game.submit_beta_input(owner_player_index, {"token": token})


func close_overlay(
	force: bool = false
) -> void:
	if not visible:
		return

	visible = false
	overlay_closed.emit()


func is_mandatory_open() -> bool:
	return (
		visible
		and mode == MODE_PREPARATION
	)


func _on_close_pressed() -> void:
	close_overlay(false)


func _unhandled_key_input(
	event: InputEvent
) -> void:
	if not visible:
		return

	if not event is InputEventKey:
		return

	if not event.pressed \
	or event.echo:
		return

	if event.keycode == KEY_ESCAPE:
		close_overlay(false)


func _render_cards() -> void:
	for child in card_row.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()

	count_label.text = (
		str(cards.size())
		+ (
			" cards"
			if cards.size() != 1
			else " card"
		)
	)

	if cards.is_empty():
		var empty := Label.new()
		empty.text = "Your Hand is empty."
		empty.add_theme_font_size_override("font_size", 20)
		card_row.add_child(empty)
		return

	var display_size := _card_display_size(
		cards.size()
	)

	for card_value in cards:
		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value
		var hand_index: int = int(
			card.get(
				"hand_index",
				-1
			)
		)

		card_row.add_child(
			_create_card_widget(
				card,
				hand_index,
				display_size
			)
		)
	call_deferred("_layout_cards")


func _card_display_size(
	card_count: int
) -> Vector2:
	var columns: int = clampi(card_count, 1, VISIBLE_CARD_LIMIT)
	# Keep a single row, sized for at most six cards; extra cards scroll sideways.
	var available_width: float = maxf(1.0, card_scroll.size.x - 36.0)
	var available_height: float = maxf(1.0, card_scroll.size.y - 32.0)
	var width_limit: float = (available_width - (columns - 1) * CARD_GAP) / columns - 20.0
	var height_limit: float = available_height - 80.0
	var width: float = maxf(1.0, minf(CARD_MAX_WIDTH, minf(width_limit, height_limit * CARD_ASPECT)))
	return Vector2(width, width / CARD_ASPECT)


func _layout_cards() -> void:
	if cards.is_empty():
		return
	card_row.columns = maxi(cards.size(), 1)
	var display_size := _card_display_size(cards.size())
	var frame_width: float = display_size.x + 20.0
	if cards.size() > VISIBLE_CARD_LIMIT:
		frame_width = maxf(frame_width, (card_scroll.size.x - 36.0 - (VISIBLE_CARD_LIMIT - 1) * CARD_GAP) / VISIBLE_CARD_LIMIT)
	for frame in card_row.get_children():
		frame.custom_minimum_size = Vector2(frame_width, display_size.y + 80.0)
		var button: TextureButton = frame.get_meta("card_button")
		button.custom_minimum_size = display_size


func _create_card_widget(
	card: Dictionary,
	hand_index: int,
	display_size: Vector2
) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(
		display_size.x + 12.0,
		display_size.y + 66.0
	)

	var selected: bool = (
		study_selection.has(hand_index) if mode == MODE_STUDY else hand_index == selected_hand_index
	)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.10,
		0.10,
		0.10,
		0.95
	)
	style.border_color = (
		Color(0.93, 0.72, 0.24, 1.0)
		if selected
		else Color(0.28, 0.28, 0.28, 1.0)
	)
	style.set_border_width_all(
		4 if selected else 2
	)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	frame.add_theme_stylebox_override(
		"panel",
		style
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var name_label := Label.new()
	name_label.text = str(
		card.get(
			"name",
			card.get(
				"id",
				"Spell"
			)
		)
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override(
		"font_size",
		16
	)
	header.add_child(name_label)

	var assignment_label := Label.new()
	assignment_label.text = _assignment_badge(
		hand_index
	)
	assignment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	assignment_label.add_theme_font_size_override(
		"font_size",
		15
	)
	assignment_label.modulate = Color(
		0.96,
		0.80,
		0.35
	)
	header.add_child(assignment_label)

	var card_button := TextureButton.new()
	frame.set_meta("card_button", card_button)
	card_button.custom_minimum_size = display_size
	card_button.ignore_texture_size = true
	card_button.stretch_mode = (
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	)
	card_button.tooltip_text = name_label.text

	var texture := _resolve_card_texture(
		card
	)

	if texture != null:
		card_button.texture_normal = texture
	else:
		var fallback := GradientTexture2D.new()
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([
			Color(0.18, 0.18, 0.18),
			Color(0.08, 0.08, 0.08)
		])
		fallback.gradient = gradient
		fallback.width = int(display_size.x)
		fallback.height = int(display_size.y)
		card_button.texture_normal = fallback

	card_button.pressed.connect(
		Callable(
			self,
			"_select_card"
		).bind(
			hand_index
		)
	)

	column.add_child(card_button)

	var hint := Label.new()
	hint.text = (
		"SELECTED"
		if selected
		else "Click to select"
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = (
		Color(0.93, 0.72, 0.24)
		if selected
		else Color(0.68, 0.68, 0.68)
	)
	column.add_child(hint)

	return frame


func _assignment_badge(
	hand_index: int
) -> String:
	if mode != MODE_PREPARATION:
		return ""
	var numbered_index: int = ready_hand_indices.find(
		hand_index
	)

	if numbered_index != -1:
		return (
			_roman_slot(
				numbered_index
			)
			+ " • "
			+ (
				"D"
				if ready_dark_sides[numbered_index]
				else "L"
			)
		)

	if quick_hand_index == hand_index:
		return (
			"Q • "
			+ (
				"D"
				if quick_dark_side
				else "L"
			)
		)

	return ""


func _select_card(
	hand_index: int
) -> void:
	if mode == MODE_STUDY:
		if study_selection.has(hand_index):
			study_selection.erase(hand_index)
		elif study_selection.size() < 2:
			study_selection.append(hand_index)
		_render_cards()
		_update_controls()
		return
	selected_hand_index = hand_index
	selected_dark = _assigned_dark_side(
		hand_index
	)

	feedback_label.text = ""

	_render_cards()
	_update_controls()


func _assigned_dark_side(
	hand_index: int
) -> bool:
	var numbered_index: int = ready_hand_indices.find(
		hand_index
	)

	if numbered_index != -1:
		return ready_dark_sides[
			numbered_index
		]

	if quick_hand_index == hand_index:
		return quick_dark_side

	return false


func _set_selected_side(
	use_dark: bool
) -> void:
	if selected_hand_index == -1:
		return

	selected_dark = use_dark

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_dark_sides[
			numbered_index
		] = selected_dark

	if quick_hand_index == selected_hand_index:
		quick_dark_side = selected_dark

	_render_cards()
	_update_controls()


func _assign_selected_numbered() -> void:
	if selected_hand_index == -1:
		return

	var existing_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if existing_index != -1:
		ready_dark_sides[
			existing_index
		] = selected_dark
		feedback_label.text = (
			"Updated "
			+ _roman_slot(existing_index)
			+ " to "
			+ _side_name(selected_dark)
			+ "."
		)
		_render_cards()
		_update_controls()
		return

	if quick_hand_index == selected_hand_index:
		quick_hand_index = -1
		quick_dark_side = false

	var max_numbered: int = int(
		current_request.get(
			"max_numbered_spells",
			3
		)
	)

	if ready_hand_indices.size() >= max_numbered:
		feedback_label.text = (
			"All numbered Spell Slots are already filled."
		)
		_update_controls()
		return

	ready_hand_indices.append(
		selected_hand_index
	)
	ready_dark_sides.append(
		selected_dark
	)

	feedback_label.text = (
		"Assigned to "
		+ _roman_slot(
			ready_hand_indices.size() - 1
		)
		+ " — "
		+ _side_name(selected_dark)
		+ "."
	)

	_render_cards()
	_update_controls()


func _assign_selected_quick() -> void:
	if selected_hand_index == -1:
		return

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_hand_indices.remove_at(
			numbered_index
		)
		ready_dark_sides.remove_at(
			numbered_index
		)

	quick_hand_index = selected_hand_index
	quick_dark_side = selected_dark

	feedback_label.text = (
		"Assigned to Quick — "
		+ _side_name(selected_dark)
		+ "."
	)

	_render_cards()
	_update_controls()


func _unassign_selected() -> void:
	if selected_hand_index == -1:
		return

	var changed: bool = false

	var numbered_index: int = ready_hand_indices.find(
		selected_hand_index
	)

	if numbered_index != -1:
		ready_hand_indices.remove_at(
			numbered_index
		)
		ready_dark_sides.remove_at(
			numbered_index
		)
		changed = true

	if quick_hand_index == selected_hand_index:
		quick_hand_index = -1
		quick_dark_side = false
		changed = true

	if changed:
		feedback_label.text = "Spell unassigned."

	_render_cards()
	_update_controls()


func _clear_preparation() -> void:
	ready_hand_indices.clear()
	ready_dark_sides.clear()
	quick_hand_index = -1
	quick_dark_side = false
	selected_hand_index = -1
	selected_dark = false
	feedback_label.text = "Preparation cleared."

	_render_cards()
	_update_controls()


func _confirm_preparation() -> void:
	var total_prepared: int = (
		ready_hand_indices.size()
		+ (
			1
			if quick_hand_index != -1
			else 0
		)
	)

	var min_spells: int = int(
		current_request.get(
			"min_spells",
			2
		)
	)

	var max_spells: int = int(
		current_request.get(
			"max_spells",
			4
		)
	)

	if total_prepared < min_spells \
	or total_prepared > max_spells:
		feedback_label.text = (
			"Prepare between "
			+ str(min_spells)
			+ " and "
			+ str(max_spells)
			+ " Spells."
		)
		_update_controls()
		return

	var payload: Dictionary = {
		"ready_hand_indices":
			ready_hand_indices.duplicate(),
		"ready_dark_sides":
			ready_dark_sides.duplicate(),
		"quick_hand_index":
			quick_hand_index,
		"quick_dark_side":
			quick_dark_side
	}

	preparation_confirmed.emit(
		payload
	)


func _update_controls() -> void:
	if mode == MODE_STUDY:
		study_confirm_button.disabled = study_selection.size() != 2
		study_confirm_button.text = "Keep selected cards (%d/2)" % study_selection.size()
		confirmation_changed.emit(study_confirm_button)
		return
	if mode != MODE_PREPARATION:
		return

	var has_selection: bool = (
		selected_hand_index != -1
	)

	var selected_name: String = (
		_card_name_by_hand_index(
			selected_hand_index
		)
		if has_selection
		else "-"
	)

	selection_label.text = (
		"Selected: "
		+ selected_name
		+ (
			" — "
			+ _side_name(selected_dark)
			if has_selection
			else ""
		)
	)

	light_button.disabled = not has_selection
	dark_button.disabled = not has_selection

	light_button.set_pressed_no_signal(
		has_selection
		and not selected_dark
	)
	dark_button.set_pressed_no_signal(
		has_selection
		and selected_dark
	)

	var max_numbered: int = int(
		current_request.get(
			"max_numbered_spells",
			3
		)
	)

	var existing_numbered: int = ready_hand_indices.find(
		selected_hand_index
	)

	if existing_numbered != -1:
		ready_button.text = (
			"Update "
			+ _roman_slot(
				existing_numbered
			)
		)
	else:
		var next_slot_index: int = ready_hand_indices.size()

		if next_slot_index < max_numbered:
			ready_button.text = (
				"Ready → "
				+ _roman_slot(
					next_slot_index
				)
			)
		else:
			ready_button.text = "Numbered full"

	ready_button.disabled = (
		not has_selection
		or (
			ready_hand_indices.size() >= max_numbered
			and existing_numbered == -1
		)
	)

	quick_button.disabled = (
		not has_selection
		or not bool(
			current_request.get(
				"quick_allowed",
				true
			)
		)
	)

	if quick_hand_index == selected_hand_index \
	and has_selection:
		quick_button.text = "Quick ✓"
	else:
		quick_button.text = "Set as Quick"

	unassign_button.disabled = (
		not has_selection
		or not _is_assigned(
			selected_hand_index
		)
	)

	slots_label.text = _slots_summary()

	var total_prepared: int = (
		ready_hand_indices.size()
		+ (
			1
			if quick_hand_index != -1
			else 0
		)
	)

	var min_spells: int = int(
		current_request.get(
			"min_spells",
			2
		)
	)
	var max_spells: int = int(
		current_request.get(
			"max_spells",
			4
		)
	)

	confirm_button.text = (
		"Confirm "
		+ str(total_prepared)
		+ "/"
		+ str(max_spells)
	)

	confirm_button.disabled = (
		total_prepared < min_spells
		or total_prepared > max_spells
	)
	confirmation_changed.emit(confirm_button)


func _slots_summary() -> String:
	var parts: Array[String] = []

	for i in range(3):
		var text_value: String = (
			_roman_slot(i)
			+ ": "
		)

		if i < ready_hand_indices.size():
			text_value += (
				_card_name_by_hand_index(
					ready_hand_indices[i]
				)
				+ " ("
				+ (
					"D"
					if ready_dark_sides[i]
					else "L"
				)
				+ ")"
			)
		else:
			text_value += "—"

		parts.append(text_value)

	var quick_text := "Quick: "

	if quick_hand_index != -1:
		quick_text += (
			_card_name_by_hand_index(
				quick_hand_index
			)
			+ " ("
			+ (
				"D"
				if quick_dark_side
				else "L"
			)
			+ ")"
		)
	else:
		quick_text += "—"

	parts.append(quick_text)

	return "   |   ".join(parts)


func _is_assigned(
	hand_index: int
) -> bool:
	return (
		ready_hand_indices.has(
			hand_index
		)
		or quick_hand_index == hand_index
	)


func _card_name_by_hand_index(
	hand_index: int
) -> String:
	for card_value in cards:
		if not card_value is Dictionary:
			continue

		var card: Dictionary = card_value

		if int(
			card.get(
				"hand_index",
				-1
			)
		) != hand_index:
			continue

		return str(
			card.get(
				"name",
				card.get(
					"id",
					"Spell"
				)
			)
		)

	return "Spell"


func _side_name(
	use_dark: bool
) -> String:
	return (
		"Dark"
		if use_dark
		else "Light"
	)


func _roman_slot(
	slot_index: int
) -> String:
	match slot_index:
		0:
			return "I"
		1:
			return "II"
		2:
			return "III"
		_:
			return str(slot_index + 1)


func _resolve_card_texture(
	card: Dictionary
) -> Texture2D:
	var spell_id: String = str(
		card.get(
			"id",
			""
		)
	)

	if spell_id == "":
		return null

	if texture_cache.has(spell_id):
		return texture_cache[
			spell_id
		]

	var school_id: String = str(
		card.get(
			"school_id",
			""
		)
	)

	var candidates: Array[String] = []
	candidates.append(VisualAssets.spell_texture_path(spell_id))

	for root in CARD_ART_ROOTS:
		if school_id != "":
			candidates.append(
				root.path_join(
					school_id
				).path_join(
					spell_id + ".png"
				)
			)

		candidates.append(
			root.path_join(
				spell_id + ".png"
			)
		)

	for path in candidates:
		if not ResourceLoader.exists(path):
			continue

		var texture = load(path)

		if texture is Texture2D:
			texture_cache[
				spell_id
			] = texture
			return texture

	var recursive_path: String = (
		_find_resource_file_recursive(
			"res://",
			spell_id + ".png",
			0
		)
	)

	if recursive_path != "" \
	and ResourceLoader.exists(recursive_path):
		var texture = load(
			recursive_path
		)

		if texture is Texture2D:
			texture_cache[
				spell_id
			] = texture
			return texture

	texture_cache[
		spell_id
	] = null

	return null


func _find_resource_file_recursive(
	directory_path: String,
	target_file_name: String,
	depth: int
) -> String:
	if depth > 7:
		return ""

	var dir := DirAccess.open(
		directory_path
	)

	if dir == null:
		return ""

	dir.list_dir_begin()

	var entry: String = dir.get_next()

	while entry != "":
		if entry == "." \
		or entry == "..":
			entry = dir.get_next()
			continue

		var full_path: String = (
			directory_path.path_join(
				entry
			)
		)

		if dir.current_is_dir():
			if entry != ".godot" \
			and entry != ".git":
				var found: String = (
					_find_resource_file_recursive(
						full_path,
						target_file_name,
						depth + 1
					)
				)

				if found != "":
					dir.list_dir_end()
					return found
		else:
			if entry.to_lower() \
			== target_file_name.to_lower():
				dir.list_dir_end()
				return full_path

		entry = dir.get_next()

	dir.list_dir_end()
	return ""
