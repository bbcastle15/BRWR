extends "res://docs/handoff-2026-10-18/checks/schools.gd"
func run():
 game = await make_game(4)
 reset_case()
 game.assign_mage_to_player(0, "bartholomaus")
 expect(game.players[0].mage.health == 10, "Bartholomaus Codex health")
 expect(game.players[0].personal_spell_id == "arcane_bond", "Bartholomaus personal spell linked")
 await cast("arcane_bond", false)
 expect(game.players[0].power == 10, "Arcane Bond does not pay on initial cast")
 await cast("macabre_order", false, 1)
 expect(game.players[0].power == 11, "Arcane Bond gains once for another Mage Summon")
 expect(game.players[1].power == 9 and game.players[1].evocations.size() == 1, "Macabre Order pays and summons")
 var ev = game.summon_evocation(0, "templarii", "arena")
 game.emit_evocation_defeated_or_removed(ev, "removed")
 await drive()
 expect(game.players[0].power == 10, "Arcane Bond loses once for own evocation removal")
 reset_case()
 await cast("arcane_bond", true)
 var room = game.get_room_by_id("arena")
 room.clear_instability()
 game.place_instability(1, "arena", 1)
 await drive()
 expect(room.instability_cubes.count(0)==1 and room.instability_cubes.count(1)==1, "Arcane Bond optional placement belongs in caster Room")
 expect(game.resolution_stack.is_empty(), "Arcane Bond does not retrigger on own placement")
 reset_case()
 await cast("deadly_bolt", false)
 expect(game.players[1].mage.get_damage()==3, "Deadly Bolt light three damage")
 reset_case()
 await cast("deadly_bolt", true)
 expect(game.players[1].mage.get_damage()==2 and game.players[2].mage.get_damage()==2, "Deadly Bolt dark room damage")
 reset_case()
 await cast("tremor", false)
 expect(game.get_room_by_id("arena").instability_cubes.count(0)==2, "Tremor light two cubes")
 reset_case()
 await cast("tremor", true)
 expect(game.get_room_by_id("arena").instability_cubes.count(-1)==2 and game.players[0].power==12, "Tremor dark rewards actual Black Rose placement")
 reset_case()
 var bear = game.summon_evocation(1, "ursa", "arena")
 expect(game.cast_ready_spell_state(0, ReadySpellState.new(game.spell_database.get_spell("duress"), true), {"target_evocation":bear,"target_model_type":"evocation"}), "Duress targets Ursa")
 await drive()
 expect(not game.players[1].evocations.has(bear), "Duress inflicts two and defeats undamaged Ursa")
 reset_case()
 game.players[0].available_cubes = 1
 bear = game.summon_evocation(1, "ursa", "arena")
 game.cast_ready_spell_state(0, ReadySpellState.new(game.spell_database.get_spell("duress"), true), {"target_evocation":bear,"target_model_type":"evocation"})
 await drive()
 expect(bear.get_damage() == 1, "Duress is capped by the one remaining cube")
 reset_case()
 game.players[0].available_cubes = 0
 await cast("deadly_bolt", true)
 expect(game.players[1].mage.get_damage() == 0 and game.players[2].mage.get_damage() == 0, "Deadly Bolt cannot deal damage without cubes")

 for card in game.spell_database.get_school_spells("lex"):
  if card.personal: continue
  for dark in [false, true]:
   reset_case()
   var side = card.get_side(dark)
   var target_ev = game.summon_evocation(1, "templarii", "arena")
   game.summon_evocation(0, "templarii", "arena")
   for owner in [1, 2, -1]: game.place_instability(owner, "arena", 1)
   var context: Dictionary = {}
   match str(side.target):
    "room": context = {"target_room_id": "arena"}
    "mage", "model": context = {"target_player_index": 1, "target_model_type": "mage"}
    "evocation": context = {"target_evocation": target_ev, "target_model_type": "evocation"}
   expect(game.cast_ready_spell_state(0, ReadySpellState.new(card, dark), context), "Lex full cast " + card.id + str(dark))
   await drive()
   expect(game.resolution_stack.is_empty() and not game.waiting_for_player_input, "Lex resolution completes " + card.id + str(dark))
 for card in game.spell_database.get_school_spells("lex"):
  if card.personal: continue
  if SpellArtResolver.get_texture(card.id, "lex") == null: print("MISSING LEX ART ",card.id)
  for dark in [false,true]:
   if not game._school_material_available(card.get_side(dark)): print("MISSING LEX MATERIAL ",card.id, dark)
 expect(game.is_school_complete("lex"), "Lex has all runtime materials and is selectable")
 print("LEX REGRESSION: %d checks, %d failures" % [checks, failures.size()])
 game.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
