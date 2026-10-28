extends CanvasLayer
var game
var index := 0
var title: Label
var cards: HBoxContainer
var details: RichTextLabel
var older: Button
var newer: Button
func _ready():
	layer = 165
	var root := PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left=70; root.offset_right=-70; root.offset_top=35; root.offset_bottom=-35
	root.theme=preload("res://tabletop_style.gd").make_theme()
	root.add_theme_stylebox_override("panel",preload("res://tabletop_style.gd").fabric_panel())
	add_child(root)
	var col:=VBoxContainer.new(); root.add_child(col)
	var nav:=HBoxContainer.new();col.add_child(nav)
	older=Button.new();older.text="← Previous";older.pressed.connect(func():index-=1;refresh());nav.add_child(older)
	title=Label.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",22);nav.add_child(title)
	newer=Button.new();newer.text="Next →";newer.pressed.connect(func():index+=1;refresh());nav.add_child(newer)
	var close:=Button.new();close.text="Close";close.pressed.connect(queue_free);nav.add_child(close)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;col.add_child(row)
	cards=HBoxContainer.new();cards.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(cards)
	details=RichTextLabel.new();details.bbcode_enabled=true;details.custom_minimum_size.x=390;details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_font_size_override("normal_font_size",20);row.add_child(details)
	index=maxi(0,game.public_history.size()-1);refresh()
func add_art(entry: Dictionary):
	if entry.get("kind") == "evocations":
		var token := Button.new()
		token.text = "+"
		token.add_theme_font_size_override("font_size", 50)
		token.custom_minimum_size = Vector2(80,80)
		token.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards.add_child(token)
	var texture: Texture2D = game.ReferenceCardPreview.card_texture(str(entry.get("kind","")),str(entry.get("id",""))) if entry.get("kind") != "physical" else null
	if entry.get("kind") == "rooms" and entry.get("flipped",false):
		var path := "res://assets/rooms/rebuilt/%s.png" % str(entry.id)
		if ResourceLoader.exists(path):texture=load(path)
	if texture != null:
		var art:=TextureRect.new();art.texture=texture;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.size_flags_horizontal=Control.SIZE_EXPAND_FILL;art.custom_minimum_size.x=240;cards.add_child(art)
	elif entry.get("kind") == "physical":
		var token := Button.new()
		token.text = "+"
		token.add_theme_font_size_override("font_size", 80)
		token.custom_minimum_size=Vector2(130,130)
		token.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		token.mouse_filter=Control.MOUSE_FILTER_IGNORE
		token.tooltip_text="Physical action";cards.add_child(token)
func refresh():
	for child in cards.get_children():cards.remove_child(child);child.queue_free()
	if game.public_history.is_empty():title.text="Match history";details.text="No actions recorded.";older.disabled=true;newer.disabled=true;return
	index=clampi(index,0,game.public_history.size()-1)
	var entry:Dictionary=game.public_history[index]
	title.text="%d / %d · Round %d · %s" % [index+1,game.public_history.size(),entry.round,entry.title]
	if int(entry.get("player",-1))>=0:title.text += " · " + ("Avatar" if AvatarRules.is_avatar(game,int(entry.player)) else "Player %d" % (int(entry.player)+1))
	older.disabled=index==0;newer.disabled=index==game.public_history.size()-1
	if entry.get("triggered",false):
		title.text+=" · TRIGGERED"
		if not entry.get("previous",{}).is_empty():add_art(entry.previous)
	add_art(entry)
	for related in entry.get("related",[]):add_art(related)
	var readable := PackedStringArray()
	for message in entry.get("messages", []):
		var text := humanize(str(message))
		if not text.is_empty(): readable.append(text)
	details.text="\n\n".join(readable)
	if details.text.is_empty():details.text="Revealed; awaiting resolution."

func humanize(message: String) -> String:
	if message.begins_with("Waiting for ") or message.begins_with("EFFECT PAUSED"):
		return ""
	var pattern := RegEx.new()
	pattern.compile("\\b[a-z][a-z0-9]*_[a-z0-9_]+\\b")
	for found in pattern.search_all(message):
		var token := found.get_string()
		# Symbol image resource paths are presentation markup, not prose.
		if message.contains("/" + token): continue
		var room = game.get_room_by_id(token)
		message = message.replace(token, room.room_name if room != null else token.replace("_", " ").capitalize())
	return message.replace(" | ", " · ").replace("attacker -1", "Black Rose").replace("owner -1", "Black Rose")
