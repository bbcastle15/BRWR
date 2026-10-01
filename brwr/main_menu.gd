extends Control

var session
var menu: PanelContainer
var message: Label
var address: LineEdit
var code: LineEdit
var host_button: Button
var join_button: Button
var solo_count: SpinBox

func _ready() -> void:
	session = preload("res://online_session.gd").new()
	session.name = "OnlineSession"
	add_child(session)
	session.status_changed.connect(_status)
	session.match_started.connect(func(): menu.hide())
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -300
	menu.offset_top = -260
	menu.offset_right = 300
	menu.offset_bottom = 260
	layer.add_child(menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	menu.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = "BLACK ROSE WARS · REBIRTH"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	solo_count = SpinBox.new()
	solo_count.min_value = 2
	solo_count.max_value = 6
	solo_count.value = 2
	solo_count.prefix = "Giocatori solo-test: "
	box.add_child(solo_count)
	_button(box, "Modalità solo-test", _solo)
	box.add_child(HSeparator.new())
	var label := Label.new()
	label.text = "PvP diretto · 2 giocatori · Internet / rete locale · UDP 27847"
	box.add_child(label)
	host_button = _button(box, "Crea partita PvP", _host)
	address = LineEdit.new()
	address.placeholder_text = "IP pubblico dell'host (oppure IP locale in LAN)"
	box.add_child(address)
	code = LineEdit.new()
	code.placeholder_text = "Codice partita comunicato dall'host"
	code.max_length = 6
	box.add_child(code)
	join_button = _button(box, "Entra nella partita PvP", _join)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(520, 64)
	box.add_child(message)
	_button(box, "Torna al menu / Annulla connessione", _reset)
	_button(box, "Chiudi gioco", func(): get_tree().quit())

func _button(box: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	box.add_child(button)
	return button

func _solo() -> void:
	if session.started or multiplayer.multiplayer_peer is ENetMultiplayerPeer: return
	var game = load("res://game.tscn").instantiate()
	game.player_count = int(solo_count.value)
	add_child(game)
	menu.hide()

func _host() -> void:
	var error: Error = session.host()
	if error != OK: _status("Impossibile aprire la porta: " + error_string(error))
	else:
		host_button.disabled = true
		join_button.disabled = true

func _join() -> void:
	if address.text.strip_edges().is_empty() or code.text.length() != 6:
		_status("Inserisci IP dell'host e codice di 6 cifre.")
		return
	var error: Error = session.join(address.text, code.text)
	if error != OK: _status(error_string(error))
	else:
		host_button.disabled = true
		join_button.disabled = true

func _status(text: String) -> void:
	message.text = text
	if session.started and not session.connected: menu.show()

func _reset() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()
