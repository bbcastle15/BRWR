extends SceneTree
var failures := 0
var checks := 0
func expect(ok: bool, message: String):
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func _initialize():
 call_deferred("run")
func run():
 var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms.json"))
 var rules = preload("res://room_variants.gd")
 var game = load("res://game.tscn").instantiate()
 game.room_database = db
 var excluded = ["emerald_rose", "thorny_clearing", "life_fountain", "indoor_forest"]
 for base in db:
  if not base.get("core", false): continue
  for variant in db:
   var expected = variant.get("playable", true) and variant.get("replaces", "") == base.id
   expect(rules.allows(base, variant) == expected, "Wrong pair: %s / %s" % [base.id, variant.id])
   game.selected_lodge_variants.clear()
   game.room_variants = {base.id: variant.id}
   var selected = game.selected_room_definition(base)
   expect(selected.id == (variant.id if expected else base.id), "Stale selection accepted: %s / %s" % [base.id, variant.id])
   if variant.id in excluded:
    expect(not rules.allows(base, variant), "Gaea scenario admitted")
  game.room_variants = {base.id: "random"}
  for i in 40:
   game.selected_lodge_variants.clear()
   var selected = game.selected_room_definition(base)
   expect(selected.id == base.id or rules.allows(base, selected), "Invalid random variant")
   expect(selected.id not in excluded, "Random selected Gaea scenario")
 game.free()
 print("ROOM FAMILY CHECKS: %d, failures: %d" % [checks, failures])
 quit(0 if failures == 0 else 1)
