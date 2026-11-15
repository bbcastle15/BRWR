extends Control

const Invite = preload("res://online_invite.gd")
const TLSConfig = preload("res://tls_config.gd")
var session
var web_host
var upnp_manager
var menu: PanelContainer
var message: Label
var address: LineEdit
var code: LineEdit
var public_address: LineEdit
var invite_link: LineEdit
var host_button: Button
var join_button: Button
var start_button: Button
var solo_button: Button
var solo_count: SpinBox
var online_count: SpinBox
var roster: Label
var room_selections: Dictionary = {}
var solo_room_selections: Dictionary = {}
var room_setup_button: Button
var solo_room_button: Button
var local_lineup: Label
var avatar_solo_start: Button
var avatar_selection: Dictionary = {}
var avatar_setup_button: Button
var mode_pages: Dictionary = {}
var mode_buttons: Dictionary = {}
var forced_school_ids: Array[String] = []
var school_checks: Array[CheckBox] = []
var school_count_label: Label
var solo_difficulty: OptionButton
var username: LineEdit

func _ready() -> void:
	theme = preload("res://tabletop_style.gd").make_theme()
	session = preload("res://online_session.gd").new()
	session.name = "OnlineSession"
	add_child(session)
	session.status_changed.connect(_status)
	session.match_started.connect(func(): menu.hide())
	session.lobby_changed.connect(_refresh_lobby)
	if not OS.has_feature("web"):
		web_host = preload("res://web_host.gd").new()
		add_child(web_host)
		upnp_manager = preload("res://upnp_manager.gd").new()
		upnp_manager.name = "UPNPManager"
		add_child(upnp_manager)

	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	var background := TextureRect.new()
	background.texture = preload("res://assets/tabletop/playmat.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu = PanelContainer.new()
	menu.theme = theme
	layer.add_child(menu)
	menu.visibility_changed.connect(func(): background.visible = menu.visible)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.anchor_left = 0.23
	menu.anchor_right = 0.77
	menu.anchor_top = 0.04
	menu.anchor_bottom = 0.96

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	menu.add_child(margin)

	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	var title := _label(box, "BLACK ROSE WARS · REBIRTH")
	title.add_theme_font_size_override("font_size", 26)
	_label(box, "Your name")
	username = LineEdit.new()
	username.name = "Username"
	username.placeholder_text = "Enter your player name"
	username.max_length = 24
	box.add_child(username)

	var navigation := HBoxContainer.new()
	box.add_child(navigation)
	for mode in ["local", "online", "solo"]:
		var button := _button(navigation, mode, _show_mode.bind(mode))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		mode_buttons[mode] = button
	for mode in ["local", "online", "solo"]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 12)
		box.add_child(page)
		mode_pages[mode] = page
	var root_box := box
	box = mode_pages.local
	_label(box, "Local match")
	_label(box, "Choose your opponents. You control every Mage on this device.")
	var solo_row := HBoxContainer.new()
	box.add_child(solo_row)
	solo_count = _count(solo_row)
	solo_count.prefix = "Rival Mages: "
	solo_count.min_value = 1
	solo_count.max_value = 5
	solo_count.value = 1
	local_lineup = _label(box, "")
	solo_count.value_changed.connect(func(_value): _refresh_local_lineup())
	username.text_changed.connect(func(_value): _refresh_local_lineup())
	_refresh_local_lineup()
	room_setup_button = _button(box, "Lodge Rooms · original / alternative", _open_room_setup)
	avatar_setup_button = _button(box, "Avatar · None", _open_avatar_setup)
	solo_button = _button(box, "Start local match", _solo)

	box = mode_pages.online
	_label(box, "Online PvP · Host and players connect to the BRWR server on Render.")
	if OS.has_feature("web"):
		_label(box, "Open the host’s invite link and press Join game.")
	else:
		var host_row := HBoxContainer.new()
		box.add_child(host_row)
		online_count = _count(host_row)
		var mages := MageDatabase.new()
		mages.load_database()
		online_count.max_value = mini(6, mages.get_mage_ids().size())
		host_button = _button(host_row, "Create online room", _host)

		public_address = LineEdit.new()
		public_address.placeholder_text = "BRWR server on Render"
		public_address.text = Invite.configured_web_base()
		public_address.editable = false
		box.add_child(public_address)
		_label(box, "Internet: no port forwarding required. Players connect to Render using WSS.")

		invite_link = LineEdit.new()
		invite_link.editable = false
		invite_link.placeholder_text = "The invite link appears after creating a room"
		box.add_child(invite_link)

		_button(box, "Copy invite link", func():
			if not invite_link.text.is_empty():
				DisplayServer.clipboard_set(invite_link.text))

		start_button = _button(box, "Start game", func(): session.start_match())
		start_button.disabled = true

	roster = _label(box, "")
	address = LineEdit.new()
	address.placeholder_text = "Paste BRWR invite link"
	box.add_child(address)

	code = LineEdit.new()
	code.placeholder_text = "Room code · filled from invite link"
	code.max_length = 128
	box.add_child(code)

	join_button = _button(box, "Join game", _join)
	box = mode_pages.solo
	_label(box, "One Mage against Possessed")
	solo_difficulty = OptionButton.new()
	solo_difficulty.add_item("Apprendista · 3 Command Cards")
	solo_difficulty.add_item("Maestro · 4 Command Cards")
	box.add_child(solo_difficulty)
	solo_room_button = _button(box, "Lodge Rooms · original / alternative", _open_room_setup.bind(true))
	_build_school_options(box)
	avatar_solo_start = _button(box, "Start solo game", _start_avatar_solo)
	box = root_box
	_show_mode("local")
	message = _label(box, "")
	message.custom_minimum_size.y = 50

	_button(box, "Return to menu / Cancel connection", _reset)
	if not OS.has_feature("web"):
		_button(box, "Exit game", func(): get_tree().quit())
	else:
		var link: String = str(JavaScriptBridge.eval("window.location.href", true))
		var invitation := Invite.parse(link)
		if not invitation.is_empty():
			address.text = invitation.address
			code.text = invitation.code
			_show_mode("online")
			_status("Invite ready. Press Join game.")
		JavaScriptBridge.eval(
			"document.addEventListener('contextmenu', function(e) { e.preventDefault(); });",
			true
		)

	_refresh_lobby()

func _label(box: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label

func _count(box: Control) -> SpinBox:
	var count := SpinBox.new()
	count.min_value = 2
	count.max_value = 6
	count.value = 2
	count.prefix = "Players: "
	count.custom_minimum_size = Vector2(190, 40)
	box.add_child(count)
	return count

func _button(box: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	box.add_child(button)
	return button

func _show_mode(mode: String) -> void:
	for key in mode_pages:
		mode_pages[key].visible = key == mode
		mode_buttons[key].button_pressed = key == mode

func _build_school_options(box: Control) -> void:
	school_count_label = _label(box, "Force Schools · 0/6 · remaining Schools are random")
	# Query the same completeness gate used by the match, without starting a game.
	var catalog = load("res://game.gd").new()
	catalog.spell_database.load_database()
	catalog.evocation_database.load_database()
	catalog.school_specialization_database = catalog.load_school_specializations()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for id in catalog.get_playable_school_ids():
		var check := CheckBox.new()
		check.text = catalog.get_school_display_name(id)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.set_meta("school_id", id)
		grid.add_child(check)
		school_checks.append(check)
		check.toggled.connect(func(selected: bool):
			if selected and not forced_school_ids.has(id) and forced_school_ids.size() < 6:
				forced_school_ids.append(id)
			elif not selected:
				forced_school_ids.erase(id)
			for item in school_checks:
				item.disabled = forced_school_ids.size() >= 6 and not item.button_pressed
			school_count_label.text = "Force Schools · %d/6 · remaining Schools are random" % forced_school_ids.size())
	catalog.free()

func _start_avatar_solo() -> void:
	_start_local(true)

func _refresh_local_lineup() -> void:
	var name_text: String = session.clean_display_name(username.text)
	var seats := PackedStringArray(["You" if name_text.is_empty() else name_text])
	for i in int(solo_count.value):
		seats.append("Rival " + str(i + 1))
	if not avatar_selection.is_empty():
		seats.append("Random Avatar" if avatar_selection.id == "random" else str(avatar_selection.id).capitalize())
	local_lineup.text = "Lodge · " + "  /  ".join(seats)

func _solo() -> void:
	_start_local(false)

func _start_local(against_avatar: bool) -> void:
	if not _accept_username(): return
	if session.started or session.connected or session.connection_started > 0:
		return
	var game = load("res://game.tscn").instantiate()
	game.local_match_mode = "solo" if against_avatar else "local"
	game.player_names = {0: session.display_name}
	game.avatar_selection = {"id": "possessed", "difficulty": "master" if solo_difficulty.selected == 1 else "apprentice"} if against_avatar else avatar_selection.duplicate(true)
	game.forced_school_ids.assign(forced_school_ids if against_avatar else [])
	game.player_count = 2
	if not against_avatar:
		var rivals := int(solo_count.value)
		game.player_count = 1 + rivals + (0 if avatar_selection.is_empty() else 1)
		for i in rivals:
			game.player_names[i + 1] = "Rival " + str(i + 1)
	game.room_variants = (solo_room_selections if against_avatar else room_selections).duplicate()
	game.beta_force_fullscreen = not OS.has_feature("web")
	add_child(game)
	menu.hide()

func _web_directory() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--web-root="):
			return arg.trim_prefix("--web-root=")
	return ProjectSettings.globalize_path("res://output/web")

func _host() -> void:
	if not _accept_username(): return
	var endpoint := Invite.websocket_address()
	if endpoint.is_empty():
		_status("Render server not configured. Set its URL in online_server_url.txt.")
		return

	session.room_variants = room_selections.duplicate()
	session.avatar_selection = avatar_selection.duplicate(true)
	var error: Error = session.host(int(online_count.value))
	if error != OK:
		_status("Unable to connect to online server: " + error_string(error))
		return

	_refresh_lobby()

func _refresh_invite() -> void:
	if invite_link == null or not session.hosting or session.room_code.is_empty():
		return

	invite_link.text = Invite.create(session.room_code)
	invite_link.tooltip_text = "BRWR online · Render relay"
	if invite_link.text.is_empty():
		_status("Render server not configured. Check online_server_url.txt.")

func _join() -> void:
	if not _accept_username(): return
	var target := address.text.strip_edges()
	var invitation := Invite.parse(target)
	if not invitation.is_empty():
		target = invitation.address
		code.text = invitation.code
	if target.is_empty() or code.text.is_empty():
		_status("Enter an invite link or room code.")
		return
	var error: Error = session.join(target, code.text)
	if error != OK:
		_status(error_string(error))
	_refresh_lobby()

func _refresh_lobby() -> void:
	var in_session: bool = session.connected or session.connection_started > 0 or session.started
	username.editable = not in_session
	solo_button.disabled = in_session
	room_setup_button.disabled = in_session
	solo_room_button.disabled = in_session
	avatar_solo_start.disabled = in_session
	avatar_setup_button.disabled = in_session
	join_button.disabled = in_session
	address.editable = not in_session
	code.editable = not in_session
	if host_button != null:
		host_button.disabled = in_session
		start_button.disabled = not session.can_start()
		online_count.editable = not in_session

	var names := PackedStringArray()
	if session.connected:
		for seat in session.seats:
			names.append(
				"%s%s"
				% [session.seat_names.get(seat, "Connecting…"), " (you)" if seat == session.local_player else ""]
			)
	roster.text = " · ".join(names)
	if host_button != null and session.hosting and not session.room_code.is_empty():
		_refresh_invite()

func _accept_username() -> bool:
	var value: String = session.clean_display_name(username.text)
	if value.is_empty():
		_status("Enter your name before joining a game.")
		username.grab_focus()
		return false
	username.text = value
	session.display_name = value
	return true

func _status(text: String) -> void:
	message.text = text
	if session.started and not session.connected:
		menu.show()

func _reset() -> void:
	if upnp_manager != null:
		upnp_manager.close_brwr_ports()
	if web_host != null:
		web_host.stop()
	session.return_to_menu()


func _open_room_setup(for_solo: bool = false) -> void:
	var selections: Dictionary = solo_room_selections if for_solo else room_selections
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
	var overlay := PanelContainer.new()
	overlay.theme = theme
	menu.get_parent().add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.hide()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	overlay.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := _label(column, "LODGE ROOMS")
	title.add_theme_font_size_override("font_size", 26)
	_label(column, "Each variant replaces only its listed Room. Rooms from unimplemented special modes are excluded.")
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	var controls: Dictionary = {}
	_button(toolbar, "All original", func(): _set_all_rooms(controls, selections, false))
	_button(toolbar, "Random variants", func(): _set_all_rooms(controls, selections, true))
	var close := _button(toolbar, "Confirm and return to menu", func():
		menu.show()
		overlay.queue_free())
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for base in definitions:
		if not bool(base.get("core", false)):
			continue
		var variants: Array = definitions.filter(func(d): return preload("res://room_variants.gd").allows(base, d))
		if variants.is_empty():
			continue
		_label(rows, str(base.name))
		var group := ButtonGroup.new()
		var choices := HFlowContainer.new()
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(choices)
		variants.push_front(base)
		variants.append({"id": "random", "name": "Random"})
		controls[str(base.id)] = {}
		for definition in variants:
			var base_id: String = str(base.id)
			var variant_id: String = str(definition.id)
			var button := Button.new()
			button.text = str(definition.name)
			button.toggle_mode = true
			button.button_group = group
			button.custom_minimum_size = Vector2(225, 185)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var path: String = "res://assets/rooms/%s.png" % variant_id
			if ResourceLoader.exists(path):
				button.icon = load(path)
				button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				button.add_theme_constant_override("icon_max_width", 160)
			button.button_pressed = str(selections.get(base_id, base_id)) == variant_id
			button.pressed.connect(func():
				if variant_id != "random":
					for other in selections.keys():
						if other != base_id and selections[other] == variant_id:
							selections[other] = other
							if controls.has(other): controls[other][other].button_pressed = true
				selections[base_id] = variant_id)
			choices.add_child(button)
			controls[base_id][variant_id] = button
		rows.add_child(HSeparator.new())
	_label(rows, "Apocalypse, Room of Rebirth and the four Gaea scenario Rooms are excluded until their modes are implemented.")


func _set_all_rooms(controls: Dictionary, selections: Dictionary, randomize_variants: bool) -> void:
	selections.clear()
	for base_id in controls:
		var selected: String = "random" if randomize_variants else str(base_id)
		selections[base_id] = selected
		controls[base_id][selected].button_pressed = true

func _open_avatar_setup() -> void:
	if session.connected or session.started: return
	var overlay := PanelContainer.new()
	menu.get_parent().add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.hide()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 30)
	overlay.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	var title := _label(column, "AVATAR MODE")
	title.add_theme_font_size_override("font_size", 30)
	_label(column, "The Avatar occupies a seat in the Lodge and controls the Black Rose. Ties and choices not resolved by priorities belong to the Crown holder.")
	var selection := OptionButton.new()
	selection.name = "AvatarSelection"
	selection.custom_minimum_size.y = 48
	selection.add_item("Disabled")
	selection.set_item_metadata(0, "")
	if not AvatarRules.available().is_empty():
		selection.add_item("Random Avatar")
		selection.set_item_metadata(1, "random")
	for definition in AvatarRules.available():
		selection.add_item(str(definition.name))
		selection.set_item_metadata(selection.item_count - 1, str(definition.id))
	for i in selection.item_count:
		if selection.get_item_metadata(i) == avatar_selection.get("id", ""): selection.select(i)
	column.add_child(selection)
	var difficulty := OptionButton.new()
	difficulty.name = "AvatarDifficulty"
	difficulty.custom_minimum_size.y = 48
	difficulty.add_item("Apprendista · 3 Comandi per fase Azione")
	difficulty.add_item("Maestro · 4 Comandi per fase Azione")
	difficulty.select(1 if avatar_selection.get("difficulty") == "master" else 0)
	column.add_child(difficulty)
	var art := TextureRect.new()
	art.texture = AvatarArt.texture("possessed")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	_label(column, "Possessed · 12 Health · 2 Strength · 2 Speed\nDominion: if it starts its activation in its Cell, place it in the Black Rose Room without revealing a Command.")
	_button(column, "Confirm and return to menu", func():
		var id: String = str(selection.get_selected_metadata())
		avatar_selection = {} if id.is_empty() else {"id": id, "difficulty": "master" if difficulty.selected == 1 else "apprentice"}
		avatar_setup_button.text = "Avatar · " + ("None" if id.is_empty() else id.capitalize())
		solo_count.min_value = 1 if id.is_empty() else 0
		solo_count.max_value = 5 if id.is_empty() else 4
		_refresh_local_lineup()
		if online_count != null: online_count.max_value = 6 if id.is_empty() else 5
		menu.show()
		overlay.queue_free())
