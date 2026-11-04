extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func quiet(g):
	g.table_shell.set_process(false)
	g.table_shell._cancel_animation()
	g.table_shell.animation_queue.clear()
	g.table_shell.phase_queue.clear()
	g.table_shell.world_placements.clear()
	g.table_shell.world_removals.clear()
	g.table_shell.attack_queue.clear()
	g.table_shell.world_tweens.clear()
	g.visual_motion_until = 0
	g.beta_hud.set_process(false)
	g.suppress_placement_feedback = true

func run():
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 1000)
	game = await create_game()
	quiet(game)
	reset_case()
	game.local_viewer_index = 0
	for card in game.spell_database.spells.values():
		if not card.avatar_command.is_empty(): cards[card.id] = card
	var shell = game.table_shell
	expect(game.is_school_complete("hex"), "Hex passes the shared completeness gate")
	expect(game.get_playable_school_ids().has("hex"), "Hex available to local/online School selection")
	var regular: Array = game.spell_database.get_school_spells("hex").filter(func(s): return not s.personal and not s.forgotten)
	expect(regular.size() == 12, "Twelve regular Hex Spells")
	for card in regular:
		expect(SpellArtResolver.get_texture(card.id, "hex") != null, "Hex texture " + card.id)
		for side in [false, true]: expect(game._school_material_available(card.get_side(side)), "Hex required material " + card.id)
	# Exercise the exact Command, not a generic instability effect.
	game.table_shell = null
	await section("tomb_reinforcements")
	expect(game.get_room_by_id("black_rose").instability_cubes == [-1], "Tomb Reinforcements places its printed BR Instability")
	expect(game.players[AVATAR].evocations.size() == 1 and game.players[AVATAR].evocations[0].evocation_id == "colossus", "Tomb summons Colossus")
	expect(game.black_rose_power == 1, "Tomb awards Power")
	reset_case()
	game.summon_evocation(0, "templarii", "black_rose")
	game.players[0].evocations[0].upgrades.append("bone_shield")
	await section("tomb_reinforcements")
	expect(game.get_room_by_id("black_rose").instability_cubes.is_empty(), "Enemy Bone Shield prevents Tomb's single Instability")
	expect(game.public_action_log.any(func(s): return s.contains("Instability prevented")), "Prevention is explained in public Log")
	expect(game.players[AVATAR].evocations.size() == 1, "Prevention does not cancel summoning")
	game.table_shell = shell
	quiet(game)
	reset_case()
	# Safe observer context reaches host and remote clients symmetrically.
	var client = await create_game(true)
	quiet(client)
	client.hide()
	client.table_shell.hide()
	client.table_shell.board_layer.hide()
	client.table_shell.notice_layer.hide()
	client.beta_hud.hide()
	client.local_viewer_index = 1
	var context := {}
	game.request_effect_choice(0, "evocation_damage_ability", context, "ability_choice", [
		{"token":"place", "value":0, "label":"Place 1 Instability"},
		{"token":"convert", "value":1, "label":"Convert 1 Instability"}], 1, 1,
		"Nigredo: choose an Instability effect in its Room.")
	var remote = NetworkSnapshot.build(game, 1)
	expect(remote.pending_input.public_description.contains("Nigredo"), "Observer knows which Evocation is resolving")
	expect(not remote.pending_input.has("options") and not remote.pending_input.has("board_options"), "Observer context does not transmit private options")
	NetworkSnapshot.apply(client, remote)
	client.beta_hud._process(0)
	expect(client.beta_hud.effect_box.visible and client.beta_hud.effect_text.text.contains("Nigredo"), "Remote viewer sees host's ongoing Nigredo choice")
	game.clear_player_input()
	context = {}
	game.request_effect_choice(1, "target_evocation", context, "ev", [{"token":"a", "value":0}, {"token":"b", "value":1}], 1, 1, "Choose an Evocation to activate under your control.")
	game.beta_hud._process(0)
	expect(game.beta_hud.effect_box.visible and game.beta_hud.effect_text.text.contains("Evocation to activate"), "Host sees remote player's explicit activation choice")
	game.clear_player_input()
	# A private Hand choice must never reveal card names to observers.
	game.request_effect_choice(0, "hand_spell", {}, "private_card", [{"token":"a", "value":0, "label":"secret card"}], 1, 1, "Pick secret card")
	expect(not str(game.get_beta_pending_input(1)).contains("secret card"), "Private card prompt remains private")
	game.clear_player_input()
	# Prepared cards retain side framing on inspection without leaking to peers.
	var spell = game.spell_database.get_spell("tearing")
	game.players[1].ready_spells.assign([ReadySpellState.new(spell, true)])
	game.player_board_spell_slots[1] = {"I":{"spell":spell,"state":"prepared","use_dark_side":true}}
	game.local_viewer_index = 1
	game.open_player_board_spell(1, "I")
	var preview = game.get_node("SpellCardPreview")
	await process_frame
	expect(preview.active_side.visible and preview.active_side.position.y > 100, "Prepared Dark side highlighted during inspection")
	expect(not game.get_player_board_spell_slot_data(1, "I", 0).has("use_dark_side"), "Prepared side stays private")
	await capture("nov01-prepared-side")
	preview.hide_preview()
	# Reproduce remote Player 2 in Cell with no physical token, but a Spell for Momentum.
	game.players[1].mage.in_cell = true
	game.players[1].available_physical_actions = 0
	game.action_activation_active = true
	game.action_activation_player_index = 1
	game.action_activation_actions_used = 0
	game.action_activation_numbered_spells_cast = 0
	game.action_activation_quick_spells_cast = 0
	expect(game._request_stepwise_action_activation(), "Cell turn requests an actual legal action")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(not client.table_shell.board_overlay.visible, "Remote Player 2's Cell turn leaves the board closed until requested")
	expect(not client.get_player_board_action_options(1, "momentum").is_empty(), "Momentum remains selectable with no physical tokens")
	client.table_shell.open_board(1)
	client.table_shell.observed_viewer = 0
	client.table_shell._process(0)
	expect(client.table_shell.board_overlay.visible and client.table_shell.shown_player == 1, "Changing the viewer does not close the new player's requested Action board")
	client.table_shell.close_board()
	client.beta_hud._on_player_input_resolved({})
	client.beta_hud._toggle_panel()
	expect(client.table_shell.board_overlay.visible and client.beta_hud.current_request.type == "action_activation_step", "Choices recovers authoritative Cell turn after hidden HUD")
	game.clear_player_input()
	game.action_activation_active = false
	client.clear_player_input()
	client.table_shell.close_board()
	quiet(game)
	# Physical caption is part of the same replicated feedback event as the flip.
	game.players[0].available_physical_actions = 2
	locate(0, "arena")
	game.process_explore_resolution({"player_index":0,"destination_room_ids":[],"context":{},"step":"start"})
	expect(shell.animation_queue.size() == 1 and shell.animation_queue[0].action == "Explore", "Explore queues one labelled physical token animation")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(client.table_shell.animation_queue.any(func(e): return e.get("action") == "Explore"), "Physical action caption reaches peer")
	shell._play_next_animation()
	expect(is_instance_valid(shell.action_notice), "Physical action caption displayed with actual token")
	await capture("nov01-physical-action")
	await create_timer(2.1).timeout
	expect(shell.animation == null, "Physical feedback finishes without blocking input")
	quiet(game)
	# Phase announcements do not block clicks or depend on a player's choice.
	game.start_phase(game.PHASE_STUDY)
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	var phase_count: int = client.table_shell.phase_queue.size()
	expect(phase_count == 1 and client.table_shell.phase_queue[0].phase == game.PHASE_STUDY, "Phase announcement reaches the other player")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(client.table_shell.phase_queue.size() == phase_count, "A repeated snapshot does not replay the phase announcement")
	shell._play_phase_notice()
	await create_timer(0.45).timeout
	expect(is_instance_valid(shell.phase_notice) and shell.phase_notice.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Centered phase ribbon is non-modal")
	await capture("nov01-phase")
	await create_timer(2).timeout
	expect(not is_instance_valid(shell.phase_notice), "Phase ribbon auto-dismisses")
	quiet(game)
	reset_case()
	game.summon_evocation(0,"templarii","arena")
	var ev = game.players[0].evocations[0]
	ev.upgrades.append("bone_shield")
	game.open_evocation_inspection(ev, true)
	expect(game.evocation_inspection.visible and game.evocation_inspection.cards.get_child_count() == 2, "Evocation inspection includes assigned Upgrade")
	await capture("nov01-evocation-inspection")
	game.evocation_inspection.hide()
	quiet(client)
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	client.table_shell._play_world_placements()
	await create_timer(1.2).timeout
	var remote_ev = client.players[0].evocations[0]
	var remote_token = client.evocation_tokens[remote_ev.get_instance_id()]
	game.suppress_placement_feedback = false
	var token = game.evocation_tokens[ev.get_instance_id()]
	game.finalize_evocation_removal(ev)
	expect(not game.evocation_tokens.has(ev.get_instance_id()) and is_instance_valid(token), "Removed model leaves authority immediately; visual survives")
	NetworkSnapshot.apply(client, NetworkSnapshot.build(game, 1))
	expect(not client.evocation_tokens.has(remote_ev.get_instance_id()) and client.table_shell.world_removals.has(remote_token), "Evocation removal is animated on the remote peer too")
	shell._play_world_removals()
	client.visual_motion_until = 0
	client.table_shell._play_world_removals()
	await create_timer(0.4).timeout
	expect(is_instance_valid(token) and token.modulate.a > 0 and token.modulate.a < 1, "Evocation visibly fades instead of disappearing")
	expect(is_instance_valid(remote_token) and remote_token.modulate.a > 0 and remote_token.modulate.a < 1, "Remote token fades at the same speed")
	await create_timer(0.6).timeout
	expect(not is_instance_valid(token) and not shell.visuals_busy(), "Fade finishes and releases the visual barrier")
	expect(not is_instance_valid(remote_token), "Remote fading token is freed")
	var mage_token = game.mage_tokens[0]
	game.visual_motion_until = 0
	game._position_model_token(mage_token, mage_token.position + Vector2(80,0), "test_next_room")
	expect(game.visual_motion_until - Time.get_ticks_msec() <= 800, "Movement gap reduced to at most 80 ms after slide")
	await create_timer(0.85).timeout
	print("NOV01 PLAYTEST: ", checks, " assertions; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
