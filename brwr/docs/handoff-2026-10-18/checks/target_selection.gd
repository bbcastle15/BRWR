extends "res://docs/handoff-2026-10-18/checks/avatar_flow.gd"

func run():
 game = await create_game()
 reset_case()
 var options = [{"token":"mage:1","value":{"player_index":1},"player_index":1,"name":"Player 2"}]
 var context = {"game":game,"caster_id":0}
 expect(not game._quest_request_single_choice(0,"model_target",context,"chosen",options,"Choose a Model."), "Human unique target requires confirmation")
 expect(game.waiting_for_player_input and game.pending_input.player_index == 0, "Confirmation belongs to human")
 game.clear_player_input()
 context = {"game":game,"caster_id":AVATAR}
 expect(game._quest_request_single_choice(AVATAR,"model_target",context,"chosen",options,"Choose a Model."), "Avatar unique target resolves immediately")
 expect(context.chosen.player_index == 1 and not game.waiting_for_player_input, "Avatar target stored without input")
 context = {}
 expect(AvatarRules.choose(game,context,"chosen",options,"Choose a Model."), "Avatar priority helper resolves sole target")
 expect(not game.waiting_for_player_input, "No Crown confirmation for forced target")
 context = {}
 options.append({"token":"mage:2","value":{"player_index":2},"player_index":2,"name":"Player 3"})
 expect(not AvatarRules.choose(game,context,"chosen",options,"Choose a Model."), "Real Avatar alternatives require Crown choice")
 expect(game.waiting_for_player_input and game.pending_input.player_index == game.crown_owner_id, "Crown retains alternative target choice")
 game.clear_player_input()
 context = {}
 expect(DruidicRules.choose(game,AVATAR,context,"chosen",[options[0]],"Choose a Model."), "Shared helper automatically selects Avatar sole target")
 expect(not game.waiting_for_player_input, "Shared helper does not pause Avatar")
 reset_case()
 locate(2,"garden")
 var evocation = game.summon_evocation(1,"colossus","black_rose")
 await drive()
 choices.clear()
 game.queue_resolution({"type":"avatar_section","stage":"effects","section":{"kind":"spell","type":"combat","effects":[{"type":"damage","amount":1}]},"context":{"game":game,"caster_id":AVATAR,"spell_target_type":"area","target_room_id":"black_rose"}})
 await drive()
 expect(game.players[0].mage.get_damage() == 1 and game.players[1].mage.get_damage() == 1, "Room damage reaches both Mages")
 expect(evocation.damage_cubes.size() == 1, "Room damage reaches Evocation too")
 expect(game.players[2].mage.get_damage() == 0, "Room damage excludes outside Mage")
 expect(choices.is_empty(), "Room damage requires no per-Model clicks")
 print("TARGET SELECTION: %d checks, %d failures" % [checks,failures.size()])
 game.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
