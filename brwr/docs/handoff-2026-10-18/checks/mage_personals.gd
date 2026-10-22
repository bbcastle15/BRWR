extends "res://docs/handoff-2026-10-18/checks/schools.gd"
func run():
 game = await make_game(4)
 for id in ["arcane_bond", "pythia_of_delphi", "the_eight_spells", "calamity", "mask_of_the_world", "demonic_crown", "alchemical_fireball", "fulu", "mystic_guide", "great_architect", "incanto_porkonus", "inspiration", "carnage", "dictat", "necroflame", "three_visions"]:
  for dark in [false,true]:
   reset_case()
   game.players[0].mage.damage_cubes.assign([1,1,2,2])
   var ev = game.summon_evocation(1,"templarii","arena")
   var card = game.spell_database.get_spell(id)
   var side = card.get_side(dark)
   var ctx: Dictionary = {}
   match str(side.target):
    "room": ctx = {"target_room_id":"arena"}
    "model", "mage": ctx = {"target_model_type":"mage", "target_player_index":1}
    "evocation": ctx = {"target_model_type":"evocation", "target_evocation":ev}
   print("MAGE CASE ",id," ",dark)
   expect(game.cast_ready_spell_state(0,ReadySpellState.new(card,dark),ctx),"Cast "+id)
   await drive()
   expect(game.resolution_stack.is_empty(),"No stall "+id)
 print("MAGE SMOKE: %d checks %d failures" % [checks,failures.size()])
 game.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
