extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	var game = load("res://game.tscn").instantiate()
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	root.add_child(game)
	await process_frame
	game.local_viewer_index = 0
	var quest_card := QuestCardState.new("shattered_illusion", "Shattered Illusion", 1, {"trigger": "test_progress"}, [], 2, 1)
	game.quest_decks[1] = [quest_card]
	game.current_moon = 1
	game.quest_manager.draw_quest(game, 0)
	var hud = load("res://beta_hud.gd").new()
	game.add_child(hud)
	hud.setup(game)
	var overlay = hud.hand_overlay
	for viewport_size in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		var single_card_height := 0.0
		for count in [1, 4, 6, 7, 8, 9, 12]:
			var hand: Array = []
			for i in range(count):
				hand.append({"hand_index": i, "id": "cube_of_lamentations", "name": "Cube of Lamentations"})
			overlay.open_preparation({"player_index": 0, "hand": hand})
			for frame in range(12):
				await process_frame
			var first: Control = overlay.card_row.get_child(0)
			var last: Control = overlay.card_row.get_child(count - 1)
			var art: TextureButton = first.get_meta("card_button")
			if count == 1:
				single_card_height = art.size.y
			check(art.size.y >= single_card_height - 20, "Adding cards must not shrink their readable height")
			check(art.size.y >= viewport_size.y * 0.40, "Card art must use a substantial part of screen height")
			check(overlay.card_row.get_child_count() == count, "Every card must remain accessible")
			check(overlay.confirm_button.get_global_rect().end.y <= root.size.y, "Confirm must stay on screen")
			check(overlay.light_button.get_global_rect().end.y <= root.size.y, "Side controls must stay on screen")
			check(overlay.card_scroll.size.x > viewport_size.x * 0.85, "Spell hand must use the width freed by moving Quests to the board")
			check(last.get_global_rect().end.y <= overlay.card_scroll.get_global_rect().end.y + 1, "Cards must fit without vertical scrolling: %s / %d" % [viewport_size, count])
			check(is_equal_approx(first.position.y, last.position.y), "All cards stay in one row")
			if last.get_global_rect().end.x > overlay.card_scroll.get_global_rect().end.x + 1:
				check(overlay.card_scroll.get_h_scroll_bar().visible, "Extra cards must scroll horizontally")
				overlay.card_scroll.ensure_control_visible(last)
				await process_frame
				check(overlay.card_scroll.scroll_horizontal > 0, "The final card must be reachable by scrolling")
			if count == 6 and OS.get_cmdline_user_args().has("screenshots"):
				overlay.card_scroll.scroll_horizontal = 0
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://output/death-school/hand-%dx%d.png" % [viewport_size.x, viewport_size.y])
			overlay._select_card(count - 1)
			overlay._set_selected_side(true)
			overlay._assign_selected_quick()
			check(overlay.quick_hand_index == count - 1 and overlay.quick_dark_side, "Last card must retain Quick/Dark assignment")
	print("HAND LAYOUT PLAYTEST: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
