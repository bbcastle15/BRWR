extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func settle():
	for i in 8: await process_frame

func clean_ui():
	game.clear_player_input()
	game.resolution_stack.clear()
	game.table_shell.close_board()
	game.beta_hud.panel.hide()
	game.beta_hud.hand_overlay.close_overlay()
	game._reference_card_preview().hide_preview()

func run():
	root.size = Vector2i(1280, 720)
	game = await create_game()
	game.local_viewer_index = 0
	game.table_shell.set_process(false)
	reset_case()
	var hud = game.beta_hud
	var shell = game.table_shell
	game.request_player_input({"type":"starting_mage_choice","player_index":0,"available_mages":[game.mage_database.get_mage_data("mors")]})
	hud._submit_starting_mage("mors")
	await settle()
	expect(hud.choice_confirmation.visible and hud.choice_confirmation.card.texture != null, "Mage confirmation shows the selected Mage card")
	expect(hud.choice_confirmation.panel.get_global_rect().end.y < root.get_visible_rect().size.y, "Styled confirmation fits a 720p screen")
	await capture("ui25-mage-confirm")
	hud.choice_confirmation._cancel()
	expect(not hud.confirmation_action.is_valid(), "Cancel clears the authoritative callback")
	clean_ui()

	var schools: Array = game.active_school_ids.duplicate()
	for id in ["death", "druidic", "chaos", "hekate", "geomancy", "illusion"]:
		if not schools.has(id): schools.append(id)
	for extent in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1024,600)]:
		root.size = extent
		game.request_player_input({"type":"study_choose_schools","player_index":0,"active_school_ids":schools})
		await settle()
		var gallery = hud.content.get_node("ObjectChoices")
		var controls = hud.content.get_node("LibraryControls")
		expect(hud.content.get_parent().vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Library has no vertical outer scroll at " + str(extent))
		expect(controls.get_global_rect().end.y <= root.get_visible_rect().size.y and controls.get_global_rect().position.y >= 0, "All Library buttons stay on screen at " + str(extent))
		expect(controls.get_child_count() == 3 and controls.get_child(2).text == "Confirm", "Undo, Clear and Confirm share a fixed row")
		expect(gallery.get_global_rect().end.y <= controls.get_global_rect().position.y, "School gallery does not cover controls")
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = gallery.get_global_rect().position + Vector2(120,120)
		root.push_input(wheel, true)
		await settle()
		expect(gallery.scroll_horizontal > 0 and hud.content.get_parent().scroll_vertical == 0, "Wheel moves Schools horizontally only")
		gallery.scroll_horizontal = 500
		hud._add_study_school(str(schools[-1]))
		await settle()
		expect(hud.content.get_node("ObjectChoices").scroll_horizontal == 500, "Drawing from a later School preserves scroll position")
		if extent.y == 720: await capture("ui25-library")
		clean_ui()

	root.size = Vector2i(1600,1000)
	reset_case()
	damage(1, [2,-1,2])
	game.player_boards[1].refresh_damage_track()
	var before: Array = game.players[1].mage.damage_cubes.duplicate()
	var count: int = game.effect_resolver.convert_damage_cubes(game.players[1].mage.damage_cubes, 0, 1, [{"owner_id":-1,"cube_index":1}], game)
	expect(count == 1 and game.players[1].mage.damage_cubes == [2,0,2], "Conversion rules change only the selected cube in place")
	expect(shell.animation_queue.back().kind == "damage_conversion", "Conversion records public visual feedback")
	expect(shell.displayed_damage(1,[]) == before, "Before conversion animation the old color remains visible")
	game.player_boards[1].refresh_damage_track()
	shell._play_next_animation()
	await create_timer(1.0).timeout
	expect(shell.board_overlay.visible and shell.animation != null, "Conversion holds the board long enough to follow")
	var original_position: Vector2 = shell.animated_node.position
	await capture("ui25-damage-conversion")
	await create_timer(0.5).timeout
	expect(shell.animated_node.position == original_position, "Conversion never moves the selected cube")
	await create_timer(2.0).timeout
	expect(shell.damage_display.is_empty() and game.players[1].mage.damage_cubes == [2,0,2], "Conversion ends on the authoritative colors, with no reordered cubes")

	# Evocation cards use the same conversion feedback, identified by their stable slot.
	clean_ui()
	game.summon_evocation(1,"cadaver","arena")
	await drive()
	var ev = game.players[1].evocations.back()
	ev.damage_cubes.assign([2])
	game.refresh_all_player_boards()
	game.effect_resolver.convert_damage_cubes(ev.damage_cubes,0,1,[],game)
	shell._play_next_animation()
	expect(shell.animated_damage_ghost and shell.damage_event.evocation_slot == ev.board_number, "Evocation conversion animates its card's cube")
	shell.close_board()
	expect(shell.evocation_damage_display.is_empty(), "Skipping a conversion releases its visual snapshot")

	# Public conversion records survive an online snapshot and deduplicate.
	var client = await create_game(true)
	client.local_viewer_index = 0
	client.table_shell.set_process(false)
	var projection = preload("res://network_projection.gd")
	projection.apply(client, projection.build(game,0))
	game.players[1].mage.damage_cubes.assign([2,2])
	game.effect_resolver.convert_damage_cubes(game.players[1].mage.damage_cubes,0,1,[{"owner_id":2,"cube_index":1}],game)
	var snapshot: Dictionary = projection.build(game,0)
	projection.apply(client,snapshot)
	expect(client.table_shell.animation_queue.filter(func(e): return e.kind=="damage_conversion").size() == 1, "Online client receives the same conversion animation")
	projection.apply(client,snapshot)
	expect(client.table_shell.animation_queue.filter(func(e): return e.kind=="damage_conversion").size() == 1, "Online conversion is not replayed twice")
	client.queue_free()
	await settle()
	clean_ui()

	reset_case()
	game.deal_damage(0,1,2,"spell")
	await drive()
	shell._play_next_animation()
	await create_timer(1.0).timeout
	expect(shell.animation != null and shell.board_overlay.visible, "Damage animation remains visible after one second")
	await create_timer(1.5).timeout
	expect(shell.animation != null and shell.board_overlay.visible, "Two damage cubes remain visible beyond two seconds")
	await capture("ui25-damage-placement")
	await create_timer(2.0).timeout
	expect(shell.animation == null and shell.damage_display.is_empty(), "Damage feedback completes without blocking rules")
	clean_ui()

	# Visually inspect all 45 Room artworks without changing Lodge geometry.
	game.hide()
	hud.visible = false
	shell.visible = false
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
	var sockets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/instability_slots.json"))
	var proof_layer := CanvasLayer.new()
	proof_layer.layer = 180
	root.add_child(proof_layer)
	var gallery := Node2D.new()
	proof_layer.add_child(gallery)
	var counter := 0
	for definition in definitions:
		if not sockets.has(str(definition.id)): continue
		var room = preload("res://room.tscn").instantiate()
		room.radius = 145
		room.room_data = definition
		room.room_id = str(definition.id)
		room.room_name = str(definition.name)
		room.position = Vector2(160 + (counter % 5)*320, 165 + ((counter % 15)/5)*325)
		gallery.add_child(room)
		var points: PackedVector2Array = room.get_art_instability_slots()
		expect(points.size()==int(definition.instability_resistance), "Measured socket count: " + str(definition.id))
		for point in points:
			var cube = preload("res://cube.tscn").instantiate()
			cube.cube_color = Color.RED
			room.add_child(cube)
			room.instability_cube_nodes.append(cube)
		room.update_instability_cube_positions()
		for i in points.size():
			var cube = room.instability_cube_nodes[i]
			expect((cube.get_transform() * (cube.size*0.5)).distance_to(points[i]) < 0.01, "Cube pivot stays centered on socket")
			var bottom: int = 5 if points.size() == 5 else mini(points.size(),4)
			var side_count: int = (points.size()-bottom)/2
			if i >= side_count and i < points.size()-side_count:
				expect(is_zero_approx(cube.rotation), "Bottom socket cubes remain horizontal")
		var label := Label.new()
		label.text = str(definition.name)
		label.position = room.position + Vector2(-140,135)
		gallery.add_child(label)
		counter += 1
		if counter % 15 == 0:
			await capture("ui25-room-sockets-%d" % (counter/15))
			for child in gallery.get_children(): child.queue_free()
			await settle()
	print("UI POLISH: ",checks," checks; failures: ",failures)
	quit(0 if failures.is_empty() else 1)
