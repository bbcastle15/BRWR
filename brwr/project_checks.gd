extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://game.tscn").instantiate()
	game.run_tests_on_ready = true
	game.enable_beta_hud = false
	game.auto_start_game_flow = false
	game.game_seed = 1232
	root.add_child(game)
	for i in range(10):
		await process_frame
	# tests.gd reports individual failures and a final ALL TESTS PASSED banner.
	quit()
