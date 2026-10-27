extends "res://docs/handoff-2026-10-18/checks/schools.gd"
func run():
 game = await make_game(4)
 reset_case()
 game.vastum_room_state.clear()
 var origin = game.players[0].mage.room_id
 var adjacent = game._beta_adjacent_room_ids(origin)[0]
 preferred["fumbling_dark_main_choice"]="branch:fumbling_dark_main_choice:target_and_optional_adjacent"
 preferred["fumbling_dark_adjacent_room"]="vastum_room:"+adjacent
 await cast("fumbling_in_the_dark",true)
 expect(game.room_has_vastum(origin),"Fumbling places first Vastum")
 expect(game.room_has_vastum(adjacent),"Fumbling places second Vastum")
 reset_case()
 game.vastum_room_state.clear()
 preferred["fumbling_dark_main_choice"]="branch:fumbling_dark_main_choice:target_and_optional_adjacent"
 preferred["fumbling_dark_adjacent_room"]="vastum_skip"
 await cast("fumbling_in_the_dark",true)
 expect(game.count_vastum()==1,"Optional second Vastum can be skipped")
 reset_case()
 game.vastum_room_state.clear()
 preferred["fumbling_dark_main_choice"]="branch:fumbling_dark_main_choice:any_room"
 preferred["fumbling_dark_any_room"]="vastum_room:"+adjacent
 await cast("fumbling_in_the_dark",true)
 expect(game.room_has_vastum(adjacent),"Alternative branch places Vastum in chosen Room")
 print("OCT26 RULES: ",checks," checks ",failures)
 quit(0 if failures.is_empty() else 1)
