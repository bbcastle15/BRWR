extends "res://docs/handoff-2026-10-18/checks/nov02_avatar_marker_playtest.gd"

func run():
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	quiet(game)
	reset_case()
	expect(game.is_school_complete("nightmare"), "Nightmare has all rules, 12 Spell images, School and Evocation cards")
	expect(game.get_playable_school_ids().has("nightmare"), "Nightmare is in the shared setup catalogue")
	expect(SpellArtResolver.get_texture("throne_of_thorns") == load("res://assets/spells/throne_of_torns.png"), "Throne of Thorns uses the supplied filename")
	var definitions: Array = ForgottenAttachments.database().jinxes
	var occupied_sectors: Array[int] = []
	for i in 3:
		game.players[1].mage.jinxes.append({"id":definitions[i].id,"progress":i,"owner_id":0})
	game.players[2].mage.jinxes.append({"id":definitions[3].id,"progress":0,"owner_id":0})
	var pharaoh: EvocationState = game.summon_evocation(0,"pharaoh","black_rose")
	expect(game.get_evocation_effective_strength(pharaoh) == pharaoh.strength + 2, "Pharaoh adds 2 for two cursed Mages, not 4 for their Jinxes")
	game.players[1].mage.jinxes.remove_at(2)
	expect(game.get_evocation_effective_strength(pharaoh) == pharaoh.strength + 2, "Removing one of several Jinxes does not reduce Pharaoh Strength")
	game.local_viewer_index = 0
	game.refresh_all_player_boards()
	game.table_shell.open_board(1)
	var board = game.player_boards[1]
	var strip = board.get_node("JinxCards")
	expect(strip.visible and strip.position.x > board.get_node("Quest_completed").position.x, "Opponent Jinx cards are beside Completed Quests")
	expect(strip.get_node("Cards").get_child(0).get_child_count() == 2, "All assigned Jinxes have public cards")
	var card: Button = strip.get_node("Cards").get_child(0).get_child(0).get_child(0)
	card.pressed.emit()
	expect(game._reference_card_preview().root.visible, "Another player can inspect the Jinx")
	expect(game._reference_card_preview().art.texture == game.ReferenceCardPreview.card_texture("jinxs",str(definitions[0].id)), "Inspection shows the actual Jinx card")
	game._reference_card_preview().hide_preview()
	await capture("nov03-public-jinxes")
	game.table_shell.close_board(true)
	quiet(game)
	for slot in range(1,4):
		ForgottenEvocations.resolve_assignment(game,{"type":"assign_nightmare","evocation_id":"umbra"},{"game":game,"caster_id":0,"target_player_index":1,"nightmare_slot":slot})
	expect(game.players[1].evocations.size() == 3, "Three Umbra occupy the three assignment slots")
	expect(game.mage_tokens[1].get_node("Label").position.y > 33, "Player identity remains below the Umbra ring")
	for i in 3:
		var ev: EvocationState = game.players[1].evocations[i]
		var token = game.evocation_tokens[ev.get_instance_id()]
		expect(token.portrait_sprite.material.get_shader_parameter("rim_color") == Color.BLACK, "Umbra has a black rim in its assigned sector")
		var ghost = token.create_visual_copy()
		expect(ghost.portrait_sprite.material.get_shader_parameter("rim_color") == Color.BLACK, "Animated Umbra keeps its black rim")
		ghost.free()
		expect(token.get_parent() == game.mage_tokens[1] and not occupied_sectors.has(token.sector), "Attached Umbra has a distinct sector: %d" % i)
		occupied_sectors.append(token.sector)
		token._compact = not (token.get_global_transform_with_canvas().x.length() * 42.0 < 30.0)
		token._process(1.0)
		var button = token.get_node("InspectButton")
		expect(not button._has_point(button.size * 0.5), "Umbra hitbox leaves the Mage clickable")
		var point: Vector2 = button.center_offset() + button.size * 0.5
		expect(button._has_point(point), "Each Umbra ring segment can be inspected/targeted")
	ForgottenEvocations.resolve_assignment(game,{"type":"assign_nightmare","evocation_id":"umbra"},{"game":game,"caster_id":0,"target_player_index":1,"nightmare_slot":1})
	expect(game.players[1].evocations.size() == 3, "A fourth assignment does not overlap an occupied Nightmare slot")
	await capture_umbra()
	var guard: EvocationState = game.summon_evocation(0,"eracleto","black_rose")
	expect(guard != null and guard.familiar_guard, "Familiar uses the ordinary authoritative Evocation collection")
	var client = await create_game(true)
	quiet(client)
	client.hide()
	client.table_shell.hide()
	client.table_shell.board_layer.hide()
	client.table_shell.notice_layer.hide()
	client.beta_hud.hide()
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 0))
	expect(client.is_school_complete("nightmare"), "Nightmare is complete on the browser/client path too")
	var remote_pharaoh: EvocationState = client.players[0].evocations[0]
	expect(client.get_evocation_effective_strength(remote_pharaoh) == game.get_evocation_effective_strength(pharaoh), "Online Pharaoh Strength is neither per-Jinx nor double-counted")
	expect(client.player_boards[1].get_node("JinxCards/Cards").get_child(0).get_child_count() == 2, "Public Jinx cards survive the remote snapshot")
	for ev in client.players[1].evocations:
		expect(client.evocation_tokens[ev.get_instance_id()].get_parent() == client.mage_tokens[1], "Online Umbra stays attached to its Mage")
	var remote_guard: EvocationState = client.players[0].evocations[1]
	expect(remote_guard.familiar_guard and remote_guard.familiar_action_available, "Online snapshot preserves Guard and the independent Familiar token")
	expect(client.evocation_tokens[remote_guard.get_instance_id()].get_parent() == client.mage_tokens[0], "Online Guard attaches to the correct Mage")
	game.players[2].mage.jinxes.clear()
	expect(game.get_evocation_effective_strength(pharaoh) == pharaoh.strength + 1, "Removing a Mage's last Jinx removes one Pharaoh bonus")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game,0))
	expect(client.get_evocation_effective_strength(client.players[0].evocations[0]) == pharaoh.strength + 1, "Online bonus changes when the last Jinx is removed")
	client.queue_free()
	await process_frame
	print("NOV03 JINX / NIGHTMARE: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)

func capture_umbra():
	if DisplayServer.get_name() == "headless": return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720,300)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for count in range(1,4):
		var mage = game.mage_token_scene.instantiate()
		mage.setup(1,game.players[1].color)
		mage.set_nightmare_attached(true)
		viewport.add_child(mage)
		mage.position = Vector2(120+(count-1)*240,130)
		mage.scale = Vector2.ONE * 2.8
		for i in count:
			var ev: EvocationState = game.players[1].evocations[i]
			var ring = preload("res://umbra_token.gd").new()
			ring.setup("umbra","Umbra",1,Color.DIM_GRAY,ev.board_number,ev)
			mage.add_child(ring)
			ring.z_index = 1
			ring.set_sector(i)
	for i in 5: await process_frame
	RenderingServer.force_draw(false)
	viewport.get_texture().get_image().save_png("res://docs/handoff-2026-10-18/evidence/nov03-umbra-ring.png")
	viewport.queue_free()
