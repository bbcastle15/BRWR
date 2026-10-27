extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func settle():
 for i in 8: await process_frame
func run():
 root.size=Vector2i(1600,1000)
 game=await create_game()
 game.local_viewer_index=0
 reset_case()
 var shell=game.table_shell
 var hud=game.beta_hud
 hud.set_process(false)
 hud.panel.hide()
 shell.animation_queue.clear()
 shell.world_placements.clear()
 game.suppress_placement_feedback=true
 var own=game.summon_evocation(0,"cadaver","black_rose")
 var enemy=game.summon_evocation(1,"cadaver","black_rose")
 for spell_id in ["athanor_eruption","deadly_bolt"]:
  var side=game.spell_database.get_spell(spell_id).light_side
  var options=game._spell_evocation_target_options(0,side,false)
  expect(not options.any(func(o):return o.value.evocation==own),spell_id+" excludes friendly Evocation")
  expect(options.any(func(o):return o.value.evocation==enemy),spell_id+" keeps enemy Evocation")
 game.suppress_placement_feedback=false
 shell.animation_queue.clear()
 var room=game.get_room_by_id("arena")
 room.add_instability_cube(-1)
 game.queue_resolution({"type":"effect_sequence","resolver_kind":"spell","index":0,"effects":[{"type":"gain_power","amount":1}],"context":{"game":game,"caster_id":0}})
 var before=game.players[0].power
 expect(not game.resolution_stack.is_empty(),"Next effect waits for world placement")
 await create_timer(2.6).timeout
 expect(game.players[0].power==before+1,"Effect resumes after placement")
 game.record_damage_feedback(AVATAR,0,[0],0)
 await create_timer(2.3).timeout
 expect(shell.damage_waiting,"Damage presentation waits for acknowledgement")
 expect(shell.receipt_buttons.get_child_count()==1 and shell.receipt_buttons.get_child(0).text=="Continue","Single Continue button")
 await capture("oct27-damage")
 game.acknowledge_damage(game.table_feedback_serial,0)
 game.acknowledge_damage(game.table_feedback_serial,1)
 game.acknowledge_damage(game.table_feedback_serial,2)
 await settle()
 expect(not shell.damage_waiting,"Acknowledgements release damage presentation")
 game.record_conversion_feedback(AVATAR,[0],[1],1)
 await create_timer(2.6).timeout
 expect(not shell.visuals_busy(),"Damage conversion completes")
 var frame={"type":"room_activation","room_id":"arena","player_index":0}
 expect(game._present_resolution_card(frame),"Room presentation opens")
 expect(game.card_presentation.awaiting_players==[0,1,2],"All humans acknowledge Room")
 var serial=game.card_presentation.serial
 game.dismiss_card_presentation(serial,0)
 expect(not game.card_presentation.is_empty(),"One acknowledgement does not finish for everyone")
 await create_timer(10.3).timeout
 expect(game.card_presentation.is_empty(),"Presentation automatically closes after ten seconds")
 hud._on_player_input_requested({"type":"study_choose_schools","player_index":0,"active_school_ids":["lex","famine","alchemy"]})
 await settle()
 expect(hud.content.get_child(0) is HBoxContainer,"Study actions are first row")
 expect(hud.content.get_child(0).get_child_count()==3,"Undo Clear Confirm grouped")
 await capture("oct27-study")
 hud._on_player_input_resolved({})
 game.pending_input={"type":"effect_choice","player_index":1,"effect_description":"Nigredo: choose an Instability effect in its Room."}
 game.waiting_for_player_input=true
 hud._process(0)
 expect(hud.effect_text.text.contains("Waiting for Player 2"),"Spectator sees waiting, not actionable Nigredo prompt")
 game.clear_player_input()
 enemy.upgrades.append("explosive_bones")
 game.open_evocation_inspection(enemy)
 await settle()
 expect(game.evocation_inspection.get_node("Content/Cards/Upgrades").get_child_count()==1,"Evocation inspection includes Upgrade art")
 await capture("oct27-evocation")
 game.evocation_inspection.hide()
 game.add_history_entry({"kind":"spells","id":"deadly_bolt","title":"Deadly Bolt"})
 game.log_resolved_effect({"type":"damage","amount":2},{"target_player_index":1})
 shell._open_log()
 await settle()
 await capture("oct27-history")
 expect(game.public_history.back().messages.back().contains("Player 2"),"History records effect target")
 for child in shell.get_children():
  if child.get_script()!=null and child.get_script().resource_path=="res://action_history.gd":child.queue_free()
 game.suppress_placement_feedback=true
 room.clear_instability()
 for i in room.get_instability_resistance():room.add_instability_cube(i%3,false)
 var camera=game.get_node("TableCamera")
 camera._cancel_power_focus(false)
 camera.position=room.global_position
 camera.zoom=Vector2.ONE*3
 await settle()
 await capture("oct27-sockets")
 print("OCT27 UI: ",checks," checks; failures: ",failures)
 quit(0 if failures.is_empty() else 1)
