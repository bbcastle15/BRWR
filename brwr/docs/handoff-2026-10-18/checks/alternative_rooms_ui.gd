extends SceneTree

var TASK := OS.get_user_data_dir() + "/"
const NetProjection = preload("res://network_projection.gd")
var game
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")
	create_timer(100).timeout.connect(func(): push_error("UI check timeout"); quit(2))

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for i in 6: await process_frame

func click(control: Control) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)
	await process_frame
	for pressed in [true, false]:
		var evt := InputEventMouseButton.new()
		evt.button_index = MOUSE_BUTTON_LEFT
		evt.pressed = pressed
		evt.position = point
		evt.global_position = point
		root.push_input(evt)
		await process_frame
	await settle()

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle()
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(TASK + filename + ".png")

func add_creature(id: String) -> EvocationState:
	var data: Dictionary = game.evocation_database.get_evocation(id)
	var ev := EvocationState.new(id, data.name, data.archetype, data.health, data.strength, data.speed, 0)
	ev.definition = data
	ev.room_id = "arena"
	game.players[0].add_evocation(ev)
	return ev

var selected_count := 0

func shift(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SHIFT
	key.physical_keycode = KEY_SHIFT
	key.pressed = pressed
	Input.parse_input_event(key)
	await process_frame

func choice(token: String):
	for node in get_nodes_in_group("board_target_choices"):
		if node is Button and node.get_meta("choice_token", "") == token and not node.is_queued_for_deletion(): return node
	return null

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	game = load("res://game.tscn").instantiate()
	game.player_count = 2
	game.beta_force_fullscreen = false
	game.network_client = true
	game.local_viewer_index = 0
	root.add_child(game)
	await settle()
	game.network_client = false
	game.current_phase = game.PHASE_ACTION
	game.game_flow_active = false
	game.clear_player_input()
	var p = game.players[0]
	p.mage.room_id = "bibliotheca"
	p.mage.room_coord = game.room_id_to_coord("bibliotheca")
	p.mage.in_cell = false
	p.hand.assign([game.spell_database.get_spell("mass_production"),game.spell_database.get_spell("liquid_fire")])
	p.ready_spells.clear()
	p.quick_spell = null
	expect(game.prepare_player_spells(0,[0],[false],1,false), "Preparation succeeds with numbered and Quick card")
	p.memories.clear()
	p.grimoire.assign([game.spell_database.get_spell("hammerfall"),game.spell_database.get_spell("lifeline")])
	game.table_shell.animation_queue.clear()
	game.table_shell._observe(false)
	AlternativeRoomRules.queue(game,[{"type":"room_payment","ready":1,"effects":[{"type":"draw_grimoire","amount":2}]}],{"game":game,"caster_id":0,"player_index":0})
	await settle()
	expect(game.waiting_for_player_input, "Payment request is pending")
	expect(choice("ready:0") != null and choice("ready:1") != null, "Both prepared cards selectable on board")
	var original_request: Dictionary = game.pending_input.duplicate(true)
	for token in ["ready:0","ready:1"]:
		await shift(true)
		expect(Input.is_key_pressed(KEY_SHIFT), "Shift held in input state")
		await click(choice(token))
		await shift(false)
		var preview = game.get_node_or_null("SpellCardPreview")
		expect(preview != null and preview.root.visible, "Shift-click opens spell preview: " + token)
		expect(game.waiting_for_player_input and game.pending_input==original_request, "Inspect preserves pending discard choice")
		expect(p.ready_spells.size()==1 and p.quick_spell!=null and p.memories.is_empty() and p.hand.is_empty(), "Inspect does not discard or draw")
		if preview != null: preview.hide_preview()
		await settle()
	await capture("bibliotheca-select")
	await click(choice("ready:0"))
	await settle()
	game.process_resolution_stack()
	await settle()
	expect(p.ready_spells.is_empty() and p.quick_spell!=null, "Normal click discards only chosen prepared card")
	expect(p.memories.size()==1 and p.memories[0].id=="mass_production", "Exactly one spell discarded")
	expect(p.hand.size()==2 and not game.waiting_for_player_input, "Draw and Room effect resume after actual selection")
	game.table_shell.animation_queue.clear()
	game.table_shell.close_board()
	game.table_shell._observe(false)
	game.beta_hud._clear_content()
	var hud = game.beta_hud
	hud.current_player_index=0
	hud.current_request={"type":"effect_choice","player_index":0}
	hud.overlay.show()
	hud.panel.show()
	hud._add_object_choice({"id":"hammerfall","name":"Hammerfall","card_kind":"spells"},func():selected_count+=1)
	await settle()
	var gallery: Button = hud.content.get_node("ObjectChoices").get_child(0).get_child(0)
	await shift(true)
	await click(gallery)
	await shift(false)
	expect(selected_count==0 and game._reference_card_preview().root.visible, "Gallery Shift-click inspects without selecting")
	game._reference_card_preview().hide_preview()
	await click(gallery)
	expect(selected_count==1,"Gallery normal click selects once")
	hud._clear_content()
	hud.panel.hide()
	# Public equipment cards stay selectable without a map token.
	var equipment := add_creature("talos_corset")
	equipment.damage_cubes.assign([1])
	game.refresh_model_tokens()
	game.refresh_all_player_boards()
	game.table_shell.animation_queue.clear()
	game.table_shell._observe(false)
	await settle()
	expect(not game.evocation_tokens.has(equipment.get_instance_id()),"Equipment has no map token")
	expect(game._evocation_board_card(0,equipment)!=null,"Equipment remains on PlayerBoard")
	var option := {"token":"evocation:0:0","owner_id":0,"evocation_index":0,"name":"Talos's Corset"}
	expect(game.show_board_target_choice(option,func():selected_count+=1),"Legal Equipment choice renders on PlayerBoard")
	await settle()
	expect(game.table_shell.board_overlay.visible,"Equipment target opens PlayerBoard")
	await click(choice(option.token))
	expect(selected_count==2,"Equipment card click selects its existing state")
	game.clear_board_target_choices()
	await settle()
	var cube_option := {"token":"damage:1:0","cube_evocation_owner":0,"cube_evocation_index":0,"name":"Damage"}
	expect(game.show_board_target_choice(cube_option,func():selected_count+=1),"Equipment damage cubes selectable on board")
	await settle()
	await click(choice(cube_option.token))
	expect(selected_count==3,"Equipment damage cube pointer click selects once")
	await capture("equipment-board")
	game.clear_board_target_choices()
	game.table_shell.close_board()
	# The inspection path still checks authoritative privacy.
	game.local_viewer_index=1
	game.open_player_board_spell(0,"Q")
	var private_preview = game.get_node("SpellCardPreview")
	expect(not private_preview.root.visible,"Other player cannot inspect hidden prepared card")
	game.local_viewer_index=0
	game.open_player_board_spell(0,"Q")
	expect(private_preview.root.visible,"Owner can still inspect prepared card")
	print("ALTERNATIVE ROOM UI: %d checks, %d failures" % [checks,failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
