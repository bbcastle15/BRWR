extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func run():
 root.size = Vector2i(1600,1000)
 game = await create_game()
 reset_case()
 for target in [1,AVATAR]:
  game.table_shell.close_board()
  game.table_shell.queue_damage_placement(target,0,[0,2])
  game.table_shell._on_request({"type":"effect_choice"})
  expect(game.table_shell.animation_queue.size()==2,"Input preserves damage queue")
  game.table_shell._play_next_animation()
  expect(game.table_shell.board_overlay.visible and game.table_shell.shown_player==target,"Target board opens fullscreen before cubes")
  expect(game.table_shell.animated_node.modulate.a==0,"Cube starts hidden during opening pause")
  if target==AVATAR: expect(game.avatar_board.expanded,"Avatar board opens fullscreen")
  expect(game.table_shell.animated_rest_position.x > -100 and game.table_shell.animated_rest_position.y > -100,"Cube destination is on its damage track, not inherited scene offsets")
  var first = game.table_shell.animated_node
  game.table_shell._on_request({"type":"effect_choice"})
  expect(game.table_shell.animation!=null and game.table_shell.shown_player==target,"New input cannot cancel active presentation")
  await create_timer(0.25).timeout
  expect(is_instance_valid(first) and first.modulate.a==0,"Board opens before the cube animation starts")
  await create_timer(0.55).timeout
  expect(game.table_shell.shown_player==target and game.table_shell.animated_node.modulate.a>0,"Cube becomes visible on fullscreen board")
  await capture("damage-fullscreen-%d"%target)
  await create_timer(0.05).timeout
  expect(game.table_shell.board_overlay.visible and game.table_shell.shown_player==target,"Board stays open between cubes")
  game.table_shell.close_board()
  expect(game.table_shell.animation==null and game.table_shell.animation_queue.is_empty(),"User can skip animation explicitly")
 expect(not game.avatar_board.expanded,"Avatar returns to table when closed")
 print("DAMAGE FULLSCREEN: ",checks," checks; failures: ",failures)
 quit(0 if failures.is_empty() else 1)
