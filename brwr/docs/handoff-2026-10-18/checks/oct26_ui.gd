extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func settle():
 for i in 10: await process_frame
func run():
 root.size=Vector2i(1600,1000)
 game=await create_game()
 game.local_viewer_index=0
 reset_case()
 var shell=game.table_shell
 var hud=game.beta_hud
 hud.set_process(false)
 var hand=hud.hand_overlay
 shell.set_process(false)
 hud.current_request={"type":"preparation"}
 hand.open_preparation({"player_index":0,"hand":[{"hand_index":0,"id":"tearing","name":"Tearing","school_id":"death"}]})
 hand._select_card(0)
 await settle()
 expect(hand.visible,"Preparation is actually visible")
 var before=hand.card_scroll.size
 hand._assign_selected_numbered()
 await settle()
 expect(hand.card_scroll.size==before,"Preparation card viewport does not resize after assignment")
 await capture("oct26-preparation")
 hand.close_overlay()
 hud.confirm_choice("Vuoi lanciare Tearing?",func(): pass)
 await settle()
 await capture("oct26-confirmation")
 hud.choice_confirmation.hide()
 game.avatar_board.refresh()
 var card=game.avatar_board.cards_root.get_child(0)
 expect(card.mouse_filter==Control.MOUSE_FILTER_STOP,"Avatar card accepts Lodge clicks")
 card.pressed.emit()
 await settle()
 expect(game._reference_card_preview().root.visible,"Lodge Avatar card opens reference")
 game._reference_card_preview().hide_preview()
 game.record_damage_feedback(AVATAR,0,[0,0],0)
 var projection = NetworkSnapshot.build(game, 1)
 expect(projection.damage_acknowledgements[str(game.table_feedback_serial)] == [1,2],"Online state includes other human acknowledgements only")
 expect(projection.public_action_log.back().contains("dealt 2 damage"),"Online state includes public action log")
 shell._play_next_animation()
 await create_timer(2.5).timeout
 expect(shell.damage_waiting and shell.board_overlay.visible,"Damage receipt waits after animation")
 expect(shell.displayed_damage(AVATAR,[]).size()==2,"Both damage cubes remain visible")
 expect(not game.acknowledge_damage(game.table_feedback_serial,0),"Attacker cannot acknowledge for others")
 expect(game.acknowledge_damage(game.table_feedback_serial,1),"Other player can acknowledge")
 shell._refresh_damage_receipt()
 expect(shell.damage_waiting,"First acknowledgement does not close for everyone")
 await capture("oct26-damage-receipt")
 expect(game.acknowledge_damage(game.table_feedback_serial,2),"Last player can acknowledge")
 shell._refresh_damage_receipt()
 expect(not shell.damage_waiting and not shell.board_overlay.visible,"Last acknowledgement closes receipt")
 shell._open_log()
 expect(shell.log_text.text.contains("dealt 2 damage"),"Log contains damage event")
 await capture("oct26-log")
 shell.log_window.hide()
 var room=game.get_room_by_id("arena")
 room.add_instability_cube(0)
 await settle()
 var cube=room.instability_cube_nodes[0]
 expect((cube.position+cube.pivot_offset).distance_to(room.get_art_instability_slots()[0])<0.01,"Instability cube centre matches artwork socket")
 print("OCT26 UI: ",checks," checks ",failures)
 quit(0 if failures.is_empty() else 1)
