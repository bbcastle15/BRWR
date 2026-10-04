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

func _ready() -> void:
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
	menu = PanelContainer.new()
	layer.add_child(menu)
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

	var solo_row := HBoxContainer.new()
	box.add_child(solo_row)
	solo_count = _count(solo_row)
	solo_button = _button(solo_row, "Modalità solo-test", _solo)
	box.add_child(HSeparator.new())

	_label(box, "PvP online · Host e giocatori si collegano al server BRWR su Render.")
	if OS.has_feature("web"):
		_label(box, "Apri il link ricevuto dall'host e premi Entra nella partita.")
	else:
		var host_row := HBoxContainer.new()
		box.add_child(host_row)
		online_count = _count(host_row)
		var mages := MageDatabase.new()
		mages.load_database()
		online_count.max_value = mini(6, mages.get_mage_ids().size())
		host_button = _button(host_row, "Crea sala PvP", _host)

		public_address = LineEdit.new()
		public_address.placeholder_text = "Server BRWR su Render"
		public_address.text = Invite.configured_web_base()
		public_address.editable = false
		box.add_child(public_address)
		_label(box, "Internet: nessun port forwarding. Tutti i PC aprono solo connessioni WSS in uscita verso Render.")

		invite_link = LineEdit.new()
		invite_link.editable = false
		invite_link.placeholder_text = "Il link Render apparirà dopo Crea sala"
		box.add_child(invite_link)

		_button(box, "Copia link d'invito", func():
			if not invite_link.text.is_empty():
				DisplayServer.clipboard_set(invite_link.text))

		start_button = _button(box, "Avvia partita", func(): session.start_match())
		start_button.disabled = true

	roster = _label(box, "")
	address = LineEdit.new()
	address.placeholder_text = "Incolla il link d'invito BRWR"
	box.add_child(address)

	code = LineEdit.new()
	code.placeholder_text = "Codice sala · compilato automaticamente dal link"
	code.max_length = 128
	box.add_child(code)

	join_button = _button(box, "Entra nella partita", _join)
	message = _label(box, "")
	message.custom_minimum_size.y = 50

	_button(box, "Torna al menu / Annulla connessione", _reset)
	if not OS.has_feature("web"):
		_button(box, "Chiudi gioco", func(): get_tree().quit())
	else:
		var link: String = str(JavaScriptBridge.eval("window.location.href", true))
		var invitation := Invite.parse(link)
		if not invitation.is_empty():
			address.text = invitation.address
			code.text = invitation.code
			_status("Invito pronto. Premi Entra nella partita.")
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
	count.prefix = "Giocatori: "
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

func _solo() -> void:
	if session.started or session.connected or session.connection_started > 0:
		return
	var game = load("res://game.tscn").instantiate()
	game.player_count = int(solo_count.value)
	game.beta_force_fullscreen = not OS.has_feature("web")
	add_child(game)
	menu.hide()

func _web_directory() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--web-root="):
			return arg.trim_prefix("--web-root=")
	return ProjectSettings.globalize_path("res://output/web")

func _host() -> void:
	var endpoint := Invite.websocket_address()
	if endpoint.is_empty():
		_status("Server Render non configurato. Inserisci l'URL reale in online_server_url.txt.")
		return

	var error: Error = session.host(int(online_count.value))
	if error != OK:
		_status("Impossibile collegarsi al server online: " + error_string(error))
		return

	_refresh_lobby()

func _refresh_invite() -> void:
	if invite_link == null or not session.hosting or session.room_code.is_empty():
		return

	invite_link.text = Invite.create(session.room_code)
	invite_link.tooltip_text = "BRWR online · Render relay"
	if invite_link.text.is_empty():
		_status("Server Render non configurato. Controlla online_server_url.txt.")

func _join() -> void:
	var target := address.text.strip_edges()
	var invitation := Invite.parse(target)
	if not invitation.is_empty():
		target = invitation.address
		code.text = invitation.code
	if target.is_empty() or code.text.is_empty():
		_status("Inserisci il link d'invito oppure il codice della sala.")
		return
	var error: Error = session.join(target, code.text)
	if error != OK:
		_status(error_string(error))
	_refresh_lobby()

func _refresh_lobby() -> void:
	var in_session: bool = session.connected or session.connection_started > 0 or session.started
	solo_button.disabled = in_session
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
				"Player %d%s"
				% [seat + 1, " (tu)" if seat == session.local_player else ""]
			)
	roster.text = " · ".join(names)
	if host_button != null and session.hosting and not session.room_code.is_empty():
		_refresh_invite()

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
