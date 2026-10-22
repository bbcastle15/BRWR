extends "res://docs/handoff-2026-10-18/checks/schools.gd"
func run():
 game = await make_game(4)
 reset_case()
 game.players[0].mage.damage_cubes.assign([1,2,3,1])
 game.players[1].mage.damage_cubes.assign([2,2,3,3])
 preferred["room_choice"] = "mage:1"
 game.queue_resolution({"type":"effect_sequence","resolver_kind":"room","effects":game.room_database.filter(func(r): return r.id == "sanctuary")[0].rebuilt_effects,"index":0,"context":{"game":game,"caster_id":0,"player_index":0,"room_id":"arena","caster_room_id":"arena"}})
 await drive()
 expect(game.players[0].mage.get_damage() == 1, "Sanctuary heals three on caster")
 expect(game.players[1].mage.get_damage() == 1, "Sanctuary also heals selected model")
 expect(decisions.filter(func(d): return d.get("choice_kind", "") == "heal_damage").size() == 2, "Both Sanctuary heals request cube selection")
 reset_case()
 var context = {"game":game,"caster_id":0}
 game.current_effect_description = "Assign a Destiny Token."
 game._quest_request_single_choice(0,"evocation_target",context,"chosen",[{"token":"only","value":1}],"Choose an Evocation.")
 expect(game.waiting_for_player_input, "A single option still requires selection")
 expect(game.pending_input.effect_description == "Choose an Evocation.", "Choice prompt replaces stale effect text")
 game.clear_player_input()
 for card in game.spell_database.spells.values():
  if not card.is_playable_side(false) or not card.is_playable_side(true):
   expect(card.has_single_effect(), "No split highlight: " + card.id)
 print("LATEST PLAYTEST: %d checks, %d failures" % [checks,failures.size()])
 game.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
