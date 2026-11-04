extends "res://docs/handoff-2026-10-18/checks/nov02_avatar_marker_playtest.gd"

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame


func run():
	root.size = Vector2i(1600, 900)
	game = await create_game()
	quiet(game)
	var selected: Array = game.active_school_ids.duplicate()
	var random_state: int = game.rng.state
	expect(game.start_game_flow(), "The ordinary game start enters setup")
	expect(game.is_school_draw_playing(), "Local/host setup presents the Library reveal")
	var intro = game.school_draw_presentation
	expect(intro.school_ids == selected and selected.size() == 6, "Six authoritative Schools keep their exact draw order")
	expect(game.rng.state == random_state, "The reveal does not consume the game RNG")
	var pending: Dictionary = game.pending_input.duplicate(true)
	game.table_shell.phase_queue.append({"round":1,"phase":"setup"})
	game.table_shell._process(0)
	expect(game.table_shell.phase_queue.size() == 1, "Other public feedback waits behind the Library reveal")
	game.table_shell.phase_queue.clear()
	expect(game.get_node("TableCamera")._table_covered(), "Camera movement and zoom are blocked during the reveal")
	await create_timer(0.45).timeout
	await capture("nov03-school-draw-shuffle")
	await click_at(Vector2(405, 490))
	expect(game.pending_input == pending, "Clicks on the presentation do not answer the underlying choice")
	expect(game.beta_hud.choice_confirmation == null or not game.beta_hud.choice_confirmation.visible, "Clicks do not open an underlying Mage confirmation")
	await create_timer(2.1).timeout
	expect(intro.revealed_count > 0 and intro.revealed_count < 6, "School cards flip in sequence")
	await capture("nov03-school-draw-dealing")
	await create_timer(4.8).timeout
	expect(intro.revealed_count == 6 and intro.playing, "All six remain visible for a readable hold")
	for i in selected.size():
		expect(intro.cards[i].get_node("Art").texture == game.ReferenceCardPreview.card_texture("schools",selected[i]), "Revealed art matches the selected School: " + selected[i])
	await capture("nov03-school-draw-result")
	root.size = Vector2i(1280, 720)
	for i in 4: await process_frame
	for card in intro.cards:
		var bounds: Rect2 = card.get_global_transform() * Rect2(Vector2.ZERO, card.size)
		expect(root.get_visible_rect().encloses(bounds), "Every School fits at laptop resolution")
	var skip_bounds: Rect2 = intro.skip_button.get_global_transform() * Rect2(Vector2.ZERO,intro.skip_button.size)
	expect(root.get_visible_rect().encloses(skip_bounds), "Skip stays in the viewport after resize")
	await capture("nov03-school-draw-laptop")
	await create_timer(2.0).timeout
	expect(intro.playing and intro.root.visible and intro.skip_button.text == "Continue", "All Schools remain visible until explicit Continue")
	await click_at(intro.skip_button.get_global_transform() * (intro.skip_button.size * 0.5))
	expect(not intro.playing and not intro.root.visible, "Continue closes the completed draw")
	expect(game.pending_input == pending and game.active_school_ids == selected and game.rng.state == random_state, "Setup, draw and RNG are unchanged after the animation")
	game.present_school_draw_once()
	expect(game.school_draw_presentation == intro and not intro.playing, "The host cannot replay its startup animation")
	game.hide()
	game.table_shell.hide()
	game.beta_hud.hide()
	root.size = Vector2i(1600,900)
	var client = await create_game(true)
	quiet(client)
	client.local_viewer_index = 1
	client.active_school_ids.assign(["nightmare"])
	expect(client.school_draw_presentation == null, "Clients wait for the host selection")
	var snapshot: Dictionary = NetworkSnapshot.build(game,1)
	NetworkSnapshot.apply(client,snapshot)
	var remote_intro = client.school_draw_presentation
	expect(remote_intro != null and remote_intro.playing and remote_intro.school_ids == selected, "Remote setup reveals the host's six Schools, not the client placeholder")
	await create_timer(0.2).timeout
	var elapsed: float = remote_intro.timeline.get_total_elapsed_time()
	NetworkSnapshot.apply(client,snapshot)
	expect(client.school_draw_presentation == remote_intro and remote_intro.timeline.get_total_elapsed_time() >= elapsed, "Repeated snapshots neither replace nor restart the reveal")
	await click_at(remote_intro.skip_button.get_global_transform() * (remote_intro.skip_button.size * 0.5))
	expect(remote_intro.playing and remote_intro.revealed_count == 6, "Skip reveals every School without bypassing confirmation")
	await click_at(remote_intro.skip_button.get_global_transform() * (remote_intro.skip_button.size * 0.5))
	expect(not remote_intro.playing and not remote_intro.root.visible, "Remote Continue closes the draw")
	NetworkSnapshot.apply(client,snapshot)
	expect(not remote_intro.playing and client.active_school_ids == selected, "Skipping does not reroll or replay on later snapshots")
	client.queue_free()
	await process_frame
	var late_client = await create_game(true)
	quiet(late_client)
	snapshot.phase = game.PHASE_ACTION
	NetworkSnapshot.apply(late_client,snapshot)
	expect(late_client.school_draw_presentation == null, "Joining an already running match does not replay setup")
	late_client.present_school_draw_once()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	root.push_input(key,true)
	expect(late_client.is_school_draw_playing(), "First Space reveals cards and still requires confirmation")
	root.push_input(key,true)
	expect(not late_client.is_school_draw_playing(), "Second Space confirms without reaching gameplay shortcuts")
	late_client.queue_free()
	game.queue_free()
	await process_frame
	print("NOV03 SCHOOL DRAW: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
