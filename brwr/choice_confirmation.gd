extends Control
signal confirmed
signal canceled
var dialog_text: String = "":
 set(value):
  dialog_text = value
  if message != null: message.text = value
var message: Label
var frame: PanelContainer
func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var shade=ColorRect.new()
 shade.color=Color(0,0,0,0.65)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 var center=CenterContainer.new()
 center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(center)
 frame=PanelContainer.new()
 frame.custom_minimum_size=Vector2(600,240)
 frame.add_theme_stylebox_override("panel",preload("res://tabletop_style.gd").panel(Color("b69a63"),Color("141b1e"),2))
 center.add_child(frame)
 var column=VBoxContainer.new()
 column.add_theme_constant_override("separation",22)
 frame.add_child(column)
 var title=Label.new()
 title.text="CONFERMA SCELTA"
 title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 title.add_theme_font_size_override("font_size",16)
 title.add_theme_color_override("font_color",Color("b69a63"))
 column.add_child(title)
 message=Label.new()
 message.text=dialog_text
 message.custom_minimum_size=Vector2(540,90)
 message.size_flags_vertical=Control.SIZE_EXPAND_FILL
 message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 message.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
 message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 message.add_theme_font_size_override("font_size",24)
 column.add_child(message)
 var buttons=HBoxContainer.new()
 buttons.alignment=BoxContainer.ALIGNMENT_CENTER
 buttons.add_theme_constant_override("separation",20)
 column.add_child(buttons)
 var cancel=Button.new()
 cancel.text="Indietro"
 cancel.custom_minimum_size=Vector2(190,52)
 cancel.pressed.connect(func(): hide(); canceled.emit())
 buttons.add_child(cancel)
 var accept=Button.new()
 accept.text="Conferma"
 accept.custom_minimum_size=Vector2(190,52)
 preload("res://tabletop_style.gd").primary_button(accept)
 accept.pressed.connect(func(): confirmed.emit())
 buttons.add_child(accept)
 hide()
func popup_centered_clamped(_size: Vector2i, _ratio: float) -> void:
 show()
