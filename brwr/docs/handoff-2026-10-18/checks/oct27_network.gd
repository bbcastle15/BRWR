extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func run():
 game=await create_game()
 game.local_viewer_index=0
 reset_case()
 var shell=game.table_shell
 shell.set_process(false)
 shell.animation_queue.clear()
 game.suppress_placement_feedback=true
 var client=await create_game(true)
 client.local_viewer_index=0
 client.table_shell.set_process(false)
 NetworkSnapshot.apply(client,NetworkSnapshot.build(game,0))
 game.table_shell=null
 var room=game.get_room_by_id("arena")
 room.add_instability_cube(0,false)
 var ev=game.summon_evocation(1,"nigredo","arena")
 var ability=game.evocation_database.get_evocation("nigredo").abilities[0]
 game.queue_resolution({"type":"evocation_damage_ability","name":ev.get_display_name(),"ability":ability,"context":{"game":game,"caster_id":1,"caster_room_id":"arena","target_room_id":"arena","spell_target_type":"room","resolver_kind":"evocation","source_evocation":ev}})
 expect(game.waiting_for_player_input and game.pending_input.player_index==1,"Nigredo choice belongs to Player 2")
 NetworkSnapshot.apply(client,NetworkSnapshot.build(game,0))
 client.beta_hud._process(0)
 expect(client.beta_hud.effect_text.text.contains("Waiting for Player 2"),"Player 1 gets spectator status")
 expect(game.submit_effect_choice(1,"ability:1"),"Nigredo conversion choice accepted")
 for i in 12:
  if not game.waiting_for_player_input:break
  var options=game.pending_input.get("options",[])
  if options.is_empty():options=game.pending_input.get("board_options",[])
  if options.is_empty():break
  game.submit_effect_choice(1,str(options[0].token))
 expect(room.instability_cubes==[1],"Nigredo converts the selected instability")
 expect(not game.waiting_for_player_input and game.resolution_stack.is_empty(),"Nigredo resolution finishes")
 NetworkSnapshot.apply(client,NetworkSnapshot.build(game,0))
 client.beta_hud._process(0)
 expect(not client.beta_hud.effect_box.visible,"Spectator stale prompt disappears after conversion")
 game.table_shell=shell
 game.suppress_placement_feedback=false
 game.record_damage_feedback(AVATAR,0,[0],0)
 var serial=game.table_feedback_serial
 expect(game.damage_acknowledgements[str(serial)]==[0,1,2],"Every human gets damage Continue")
 var session=load("res://online_session.gd").new()
 root.add_child(session);session.game=game;session.hosting=true;session.connected=true;session.peer_players={"remote":1};session.receiving={"remote":true}
 game.network_session=session
 session._handle_game_message("remote",{"op":"ack_damage","serial":serial})
 expect(game.damage_acknowledgements[str(serial)]==[0,2],"Authenticated peer acknowledges only itself")
 session._handle_game_message("unknown",{"op":"ack_damage","serial":serial})
 expect(game.damage_acknowledgements[str(serial)]==[0,2],"Unknown peer cannot acknowledge")
 game.acknowledge_damage(serial,0);game.acknowledge_damage(serial,2)
 shell.animation_queue.clear();shell.damage_display.clear()
 game.record_conversion_feedback(AVATAR,[0],[1],1)
 NetworkSnapshot.apply(client,NetworkSnapshot.build(game,0))
 var count=client.table_shell.animation_queue.size()
 NetworkSnapshot.apply(client,NetworkSnapshot.build(game,0))
 expect(client.table_shell.animation_queue.size()==count,"Conversion feedback deduplicated online")
 expect(client.table_shell.animation_queue.any(func(e):return e.has("old_owner")),"Client queues outgoing/incoming converted cubes")
 game.network_session=null;session.connected=false;session.queue_free()
 print("OCT27 NETWORK: ",checks," checks; failures: ",failures)
 quit(0 if failures.is_empty() else 1)
