extends "res://docs/handoff-2026-10-18/checks/avatar_board_ui.gd"
func run():
 root.size = Vector2i(1600,1000)
 game = await create_game()
 game.table_shell.set_process(false)
 reset_case()
 locate(0,"arena")
 locate(AVATAR,"black_rose")
 locate(1,"garden")
 locate(2,"garden")
 var shell = game.table_shell
 game.queue_resolution({"type":"effect_sequence","resolver_kind":"room","effects":[{"type":"damage","amount":1,"target":"room","range":1}],"index":0,"context":{"game":game,"player_index":0,"caster_id":0,"room_id":"arena","target_room_id":"black_rose"}})
 await drive()
 expect(game.players[AVATAR].mage.get_damage()==1,"Arena actually damages Avatar")
 expect(shell.animation_queue.any(func(e): return e.player==AVATAR and e.kind=="damage"),"Arena queues Avatar animation")
 game.card_presentation={"serial":991,"kind":"spells","id":"possessed_energy_of_the_rose","title":"Reaction"}
 shell.sync_card_presentation()
 expect(shell._has_damage_presentation(),"Reaction card preserves pending damage")
 game.card_presentation.clear()
 shell.sync_card_presentation()
 shell._play_next_animation()
 expect(shell.shown_player==AVATAR and game.avatar_board.expanded,"Arena damage opens Avatar fullscreen")
 expect(shell.displayed_damage(AVATAR,[]).is_empty(),"New damage is absent before placement")
 await create_timer(0.58).timeout
 await capture("damage-v2-avatar-placement")
 await create_timer(0.3).timeout
 shell.close_board()
 reset_case()
 game.players[1].mage.damage_cubes.assign([2,2,2,2,2,2,2,2,2])
 game.player_boards[1].refresh_damage_track()
 game.deal_damage(0,1,2,"spell")
 await drive()
 expect(shell.displayed_damage(1,[]).size()==9,"Defeat retains previous nine damage cubes")
 shell._play_next_animation()
 expect(shell.shown_player==1,"Defeated player board opens")
 expect(game.player_boards[1].get_node("DamageTrack/DamageSlot_8/DamageCube").visible,"Existing damage stays visible")
 expect(game.player_boards[1].get_node_or_null("DamageTrack/DamageSlot_9/DamageCube")==null,"New cube is not shown prematurely")
 await create_timer(0.75).timeout
 expect(shell.displayed_damage(1,[]).size()>=10,"Placed cube remains between placements")
 await create_timer(0.85).timeout
 expect(is_instance_valid(shell.defeat_notice) and shell.defeat_notice.text=="Player 2 defeated","Defeat box follows last damage cube")
 expect(shell.displayed_damage(1,[]).size()==11,"All lethal damage remains during defeat pulse")
 expect(game.player_boards[1].get_node("HealthLabel").text=="HP: 0/11","Defeat display shows zero remaining health")
 await capture("damage-v2-defeated")
 await create_timer(2.2).timeout
 expect(shell.damage_display.is_empty() and not shell.board_overlay.visible,"Presentation releases snapshots after defeat")
 expect(game.players[1].mage.in_cell,"Rules still place defeated Mage in Cell")
 print("DAMAGE V2: ",checks," checks; failures: ",failures)
 quit(0 if failures.is_empty() else 1)
