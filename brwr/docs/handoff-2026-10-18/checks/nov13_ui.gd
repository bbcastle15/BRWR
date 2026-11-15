extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"

func run() -> void:
	root.size = Vector2i(1600,1000)
	game = await create_game()
	reset_case()
	game.local_viewer_index = 0
	game.players[1].mage.in_cell = false
	var hud = game.beta_hud
	var selected: Array = []
	hud.current_request = {"type":"evocation_phase_activations"}
	var plans := [{"path":[], "label":"No attack", "timing":"none", "callback":func(): selected.append("skip")},
		{"path":[], "label":"Attack", "timing":"before", "board_target":{"player_index":1}, "callback":func(): selected.append("attack")}]
	hud._choose_attack_order(plans, "arena")
	expect(hud.content.get_child_count() == 2 and hud.content.get_child(0).text == "Move → Attack", "Activation offers just the two orders")
	hud.content.get_child(0).pressed.emit()
	expect(selected == ["attack"], "Order selection executes sole legal attack instead of move-only plan")
	plans.append({"path":["crypt"], "label":"Move", "timing":"none", "callback":func(): selected.append("move")})
	hud._choose_attack_order(plans, "arena")
	hud.content.get_child(1).pressed.emit()
	expect(selected == ["attack","attack"], "Attack first submits the attack before asking for a destination")
	hud.current_request.clear()
	var board = game.player_boards[1]
	board.refresh_action_tokens()
	var action = board.get_node("PhysicalAction0")
	expect(action.get_node("Face").material.get_shader_parameter("rim_color") == game.players[1].color and not action.get_node("Face").material.get_shader_parameter("exhausted"), "Available action has player border and four-point star")
	game.players[1].available_physical_actions = 0
	board.refresh_action_tokens()
	expect(action.get_node("Face").material.get_shader_parameter("exhausted"), "Exhausted action shows red cross")
	game.players[1].available_physical_actions = 1
	board.refresh_action_tokens()
	PestilenceRules.assign(game, 0, 1, 1)
	expect(game.players[1].mage.infectio_tokens == [0], "Infectio uses authoritative Mage state")
	expect(game.table_feedback_events.any(func(e): return e.get("kind") == "infectio"), "Infectio emits networked placement feedback")
	board.refresh_destiny_tokens()
	var token = board.get_node_or_null("DestinyTokens/InfectioToken0")
	expect(token != null and token.texture == game.ReferenceCardPreview.card_texture("tokens", "infectio"), "Infectio renders art with owner cube")
	game.table_shell._play_next_animation()
	expect(game.table_shell.animated_trophy_ghost and game.table_shell.animated_node != null, "Infectio uses placement animation")
	game.table_shell.set_process(false)
	if game.table_shell.animation != null: game.table_shell.animation.custom_step(1.2)
	game.table_shell._show_board(1)
	await capture("nov13-infectio-placement")
	print("NOV13 UI: %d checks; %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
