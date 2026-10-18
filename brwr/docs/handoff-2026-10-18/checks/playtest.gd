extends SceneTree

var game
var checks := 0
var failures: Array[String] = []
var decisions: Array = []
var preferred: Dictionary = {}
var feed := false
var chosen_room := ""
var move_rooms: Array[String] = []

func _initialize() -> void:
	call_deferred("run")
	create_timer(150).timeout.connect(func(): push_error("Playtest regression timeout"); quit(2))

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func make_game(count: int):
	var g = load("res://game.tscn").instantiate()
	g.player_count = count
	g.enable_beta_hud = false
	g.run_tests_on_ready = true
	g.auto_start_game_flow = false
	g.beta_force_fullscreen = false
	root.add_child(g)
	await process_frame
	await process_frame
	return g

func locate(player: int, room: String) -> void:
	game.players[player].mage.in_cell = false
	game.players[player].mage.room_id = room
	game.players[player].mage.room_coord = game.room_id_to_coord(room)

func reset_case() -> void:
	game.resolution_stack.clear()
	game.clear_player_input()
	game.trigger_window_active = false
	game.trigger_window_queue.clear()
	game.trigger_window_stack.clear()
	game.current_phase = game.PHASE_ACTION
	game.crown_owner_id = 0
	game.current_phase_play_order.assign([0, 1, 2, 3])
	game.resolution_visual_yield_active = false
	game.active_events = [null, null, null]
	game.card_presentation.clear()
	game.processing_resolution_stack = false
	game.game_has_ended = false
	game.game_flow_active = false
	for id in game.room_id_by_coord.values():
		var room = game.get_room_by_id(id)
		room.clear_instability()
		room.flipped = false
		room.activated_this_turn = false
	for player in game.players:
		player.evocations.clear()
		player.active_spells.clear()
		player.revealed_spells.clear()
		player.ready_spells.clear()
		player.quick_spell = null
		player.active_quests.clear()
		player.completed_quests.clear()
		player.available_cubes = 25
		player.starved_cubes = 0
		player.mage.damage_cubes.clear()
		player.mage.health = 11
		player.mage.destiny_tokens.clear()
		player.mage.jinxes.clear()
		player.mage.infectio_tokens.clear()
		player.power = 10
		player.available_physical_actions = 2
		player.hand.clear()
		player.trophies.clear()
		locate(player.player_index, "arena")
	chosen_room = ""
	move_rooms.clear()
	decisions.clear()
	preferred.clear()
	game.stored_evocation_owner_cubes.clear()
	game.black_rose_power = 0
	feed = false

func starved(player: int, amount: int) -> void:
	game.players[player].starved_cubes = game.players[player].take_cubes(amount)

func mage_context(target: int = 1) -> Dictionary:
	return {"game":game, "caster_id":0, "caster_room_id":game.players[0].mage.room_id, "target_player_index":target, "target_model_type":"mage", "spell_target_type":"mage"}

func drive() -> void:
	for i in 180:
		await process_frame
		if game.waiting_for_player_input:
			var request: Dictionary = game.pending_input.duplicate()
			decisions.append(request)
			if request.type == "trigger_decision":
				expect(game.submit_trigger_decision(int(request.player_index), int(request.options[0].queue_index)), "Trigger accepted")
			elif request.type == "effect_choice":
				var options: Array = request.board_options if bool(request.get("board_only", false)) else request.options
				var picked: Array = []
				if request.get("context_key") == "famine_feed_branch":
					for option in options:
						if option.token == ("feed:alternative" if feed else "feed:normal"):
							picked = [option.token]
				elif request.get("choice_kind") in ["secondary_room", "movement_destination"]:
					var desired: String = chosen_room
					if request.choice_kind == "movement_destination":
						desired = move_rooms.pop_front() if not move_rooms.is_empty() else FamineRules.target_room(game, game.pending_effect_choice_context)
					for option in options:
						if option.get("room_id", "") == desired:
							picked = [option.token]
				if preferred.has(str(request.context_key)):
					var wanted = preferred[str(request.context_key)]
					if wanted is int:
						picked = [options[int(wanted)].token] if int(wanted) >= 0 else []
					else:
						picked = [wanted]
				if picked.is_empty() and not preferred.has(str(request.context_key)):
					for j in mini(int(request.max_select), options.size()):
						picked.append(options[j].token)
				var selection = picked[0] if int(request.max_select) == 1 and not picked.is_empty() else picked
				expect(game.submit_effect_choice(int(request.player_index), selection), "Choice accepted: " + str(request.context_key))
			else:
				expect(false, "Unexpected input " + str(request))
				return
		else:
			game.process_resolution_stack()
		if not game.waiting_for_player_input and game.resolution_stack.is_empty() and not game.trigger_window_active:
			return
		await process_frame
	expect(false, "Resolution stalled: " + str(game.resolution_stack))

func cast(id: String, dark: bool, owner: int = 0, target: int = 1) -> void:
	var card: SpellCardState = game.spell_database.get_spell(id)
	var side: Dictionary = card.get_side(dark)
	var context: Dictionary = {}
	if not side.type in ["trap", "protection"]:
		if side.target == "room":
			context["target_room_id"] = game.players[owner].mage.room_id
		elif side.target in ["model","mage"]:
			context = {"target_player_index": target, "target_model_type":"mage"}
	expect(game.cast_ready_spell_state(owner, ReadySpellState.new(card, dark), context), "Cast queued " + id)
	await drive()

func event(kind: String, source: int = 1, amount: int = 1) -> GameEvent:
	var evt := GameEvent.new(kind)
	evt.source_player_index = source
	evt.source_model_type = "mage"
	evt.source_room_id = game.players[source].mage.room_id
	evt.amount = amount
	evt.action_type = "spell"
	return evt

func effects(es: Array, ctx: Dictionary) -> void:
	DruidicRules.sequence(game, es, ctx)
	await drive()

func ongoing(id: String, dark: bool, owner: int = 0, target: int = -1, room: String = "") -> ActiveSpellState:
	var a := ActiveSpellState.new(game.spell_database.get_spell(id), owner, dark, target)
	if not room.is_empty(): a.context["target_room_id"] = room
	game.players[owner].active_spells.append(a)
	return a

func run() -> void:
	game = await make_game(4)
	reset_case()
	var pupa = game.summon_evocation(0, "pupa", "arena")
	var corset = game.summon_evocation(0, "talos_corset", "arena")
	var side: Dictionary = game.spell_database.get_spell("bewitching_garments").light_side
	var targets: Array = game._spell_evocation_target_options(0, side, false)
	expect(targets.size() == 1 and targets[0].value.evocation == pupa, "Bewitching Garments excludes Equipment")
	var upgrade_context := {"game":game,"caster_id":0}
	expect(ForgottenAttachments.assign_upgrade(game,0,pupa,upgrade_context,{"id":"grafted_crossbow"}), "Upgrade assignment succeeds")
	expect(pupa.upgrades == ["grafted_crossbow"], "Upgrade belongs to the Evocation")
	preferred["order"]="before"
	preferred["attack_target"]="mage:1"
	preferred["move_room"]="room:arena"
	game.queue_resolution({"type":"command","player_index":0,"evocation_index":0,"context":{"extended_activation":true}})
	await drive()
	expect(game.players[0].available_physical_actions == 1, "Command consumes exactly one physical token")
	expect(game.players[1].power == 9 and game.players[0].power == 11, "Crossbow replaces attack with one Power stolen")
	expect(game.players[1].mage.get_damage() == 0, "Crossbow deals no physical damage to Mage")
	expect(decisions.filter(func(d): return d.get("context_key") == "order").size() == 1, "One activation order decision")
	reset_case()
	var a = game.summon_evocation(0, "cadaver", "arena")
	var b = game.summon_evocation(0, "cadaver", "arena")
	ongoing("talos_intervention", false, 0)
	await effects([{"type":"damage","amount":2}], {"game":game,"caster_id":1,"caster_room_id":"arena","spell_target_type":"room","target_room_id":"arena"})
	var protected_count := int(a.upgrades.has("hyperdermis")) + int(b.upgrades.has("hyperdermis"))
	expect(protected_count == 1, "Talos protects and upgrades exactly one Evocation in simultaneous area damage")
	expect((a.get_damage() == 0 and game.is_evocation_in_play(a) and not game.is_evocation_in_play(b)) or (b.get_damage() == 0 and game.is_evocation_in_play(b) and not game.is_evocation_in_play(a)), "Other Evocation still suffers lethal area damage")
	expect(game.players[0].active_spells.is_empty(), "Protection consumed once")
	for dark in [false,true]:
		reset_case()
		await cast("rotten", dark)
		game.players[1].mage.damage_cubes.assign([2,2])
		expect(game.place_mage_in_room_direct(1,"garden"), "Opponent enters green Room")
		await drive()
		expect(game.players[0].active_spells.is_empty(), "Rotten triggers with either stored orientation")
		expect(game.players[1].mage.get_damage()==4 and game.players[1].mage.damage_cubes.count(0)==4, "Rotten inflicts two and converts two")
	reset_case()
	var owned = game.summon_evocation(0,"pupa","arena")
	preferred["target_evocation"]="quest_dummy"
	var quest_effects: Array = game.quest_database.get_quest("warrior_wizard").effects if false else [{"type":"remove_evocation_with_max_health","max_health":3,"target":"evocation","range":"*"},{"type":"place_instability","amount":1,"target":"room","range":0}]
	DruidicRules.sequence(game,quest_effects,{"game":game,"caster_id":0,"caster_room_id":"arena"},"quest")
	await drive()
	expect(game.is_evocation_in_play(owned), "Dummy target avoids forced removal of sole own Evocation")
	expect(game.get_room_by_id("arena").instability_cubes.count(0)==1, "Next Quest sentence still resolves after Dummy target")
	reset_case()
	owned=game.summon_evocation(0,"pupa","arena")
	preferred["target_evocation"]="evocation:0:0"
	DruidicRules.sequence(game,[quest_effects[0]],{"game":game,"caster_id":0,"caster_room_id":"arena"},"quest")
	await drive()
	expect(not game.is_evocation_in_play(owned), "Player can explicitly remove own Evocation")
	reset_case()
	game.players[0].hand.assign([game.clone_spell_card(game.spell_database.get_spell("wrath_of_the_jackal_god"))])
	var forgotten = game.players[0].hand[0]
	game.current_phase = game.PHASE_STUDY
	game.request_study_optional_discard(0)
	expect(game.submit_study_optional_discard(0,0), "Forgotten Study discard accepted")
	expect(game.players[0].hand.is_empty() and game.forgotten_removed_from_game.has(forgotten), "Forgotten discarded from Study removed from game")
	reset_case()
	game.players[0].hand.assign([game.clone_spell_card(game.spell_database.get_spell("wrath_of_the_jackal_god"))])
	forgotten=game.players[0].hand[0]
	game.study_parallel_active=true
	game.study_parallel_requests={0:{"type":"study_optional_discard"},1:{"type":"study_optional_discard"}}
	expect(game._submit_parallel_study_optional_discard(0,0), "Parallel Study Forgotten discard accepted")
	expect(game.forgotten_removed_from_game.has(forgotten), "Parallel discard removes Forgotten")
	game.study_parallel_active=false
	game.study_parallel_requests.clear()
	reset_case()
	game.summon_evocation(0,"nigredo","arena")
	game.summon_evocation(1,"pupa","arena")
	await cast("mass_production",false)
	var choices: Dictionary = decisions.filter(func(d):return d.get("context_key")=="school_model")[0]
	expect(choices.options.size()==2 and choices.options.all(func(o):return o.owner_id==0 and o.name.begins_with("Pupa")), "Mass Production offers only own Pupa")
	expect(game.players[0].evocations[0].get_damage()==0 and game.players[1].evocations[0].get_damage()==0, "No damage to Nigredo or opponent Pupa")
	expect(game.players[0].evocations[1].damage_cubes==[-1], "Chosen Pupa receives one Black Rose damage")
	for lethal in [false,true]:
		reset_case()
		var anubis=game.summon_evocation(0,"anubis","arena")
		if lethal: game.players[1].mage.damage_cubes.assign([0,0,0,0,0,0,0,0,0])
		preferred["order"]="before"
		preferred["attack_target"]="mage:1"
		preferred["move_room"]="room:arena"
		game.activate_evocation(anubis,0,{})
		await drive()
		expect(game.players[1].mage.jinxes.is_empty() if lethal else game.players[1].mage.jinxes.size()==1,"Anubis Jinx follows surviving/defeated target rule")
		expect(game.players[1].mage.in_cell == lethal,"Anubis defeat resolves before follow-up")
	reset_case()
	var context := {"game":game,"caster_id":0}
	expect(ForgottenAttachments.assign_jinx(game,0,1,context,{"id":"vulnerability"}),"First Vulnerability assigns without triggering itself")
	expect(not game.waiting_for_player_input,"New Vulnerability does not offer bonus damage")
	context={"game":game,"caster_id":0}
	expect(not ForgottenAttachments.assign_jinx(game,0,1,context,{"id":"divine_dance"}),"Existing Vulnerability offers optional damage")
	game.clear_player_input()
	reset_case()
	var winged=game.summon_evocation(0,"pupa","arena")
	ForgottenAttachments.assign_upgrade(game,0,winged,{}, {"id":"pegasus_feathers"})
	preferred["order"]="before"
	preferred["attack_target"]=-1
	preferred["move_room"]="room:arena"
	preferred["forgotten_optional"]="use"
	game.activate_evocation(winged,0,{})
	await drive()
	var prompts: Array=decisions.filter(func(d):return d.get("context_key")=="forgotten_optional")
	expect(prompts.size()==1 and prompts[0].prompt.contains("Pegasus") and prompts[0].prompt.contains("place 1 Instability"), "Pegasus prompt names card and effect")
	expect(game.get_room_by_id("arena").instability_cubes.count(0)==1, "Pegasus applies one instability at end of activation")
	reset_case()
	game.create_forgotten_deck()
	expect(game.forgotten_deck.any(func(c):return c.id=="wrath_of_the_jackal_god"), "Anubis summon present before choosing Mage")
	expect(game.assign_mage_to_player(0,"anubis"),"Anubis Mage available")
	expect(game.players[0].personal_spell_id=="eternal_curse" and game.players[0].mage.health==11,"Anubis stats and personal spell")
	expect(not game.forgotten_deck.any(func(c):return c.id=="wrath_of_the_jackal_god"),"Anubis Mage excludes summon Forgotten")
	game.create_forgotten_deck()
	expect(not game.forgotten_deck.any(func(c):return c.id=="wrath_of_the_jackal_god"),"Exclusion retained when deck is recreated")
	locate(0,"arena")
	locate(1,"arena")
	game.players[1].mage.damage_cubes.assign([2])
	await cast("eternal_curse",false)
	expect(game.players[1].mage.damage_cubes.count(0)>=3 and game.players[1].mage.jinxes.size()==1,"Eternal Curse Light converts, damages and assigns Jinx")
	reset_case()
	game.players[1].mage.jinxes.assign([{"id":"vulnerability","progress":0}])
	game.players[1].mage.damage_cubes.assign([0,0,0,0,0,0,0,0,0])
	await cast("eternal_curse",true)
	expect(game.players[1].mage.in_cell,"Eternal Curse Dark deals 1 plus Jinx count in one damage effect")
	expect(game.players[0].evocations.any(func(ev):return ev.evocation_id=="pharaoh" and ev.room_id=="arena"),"Eternal Curse Dark summons Pharaoh where victim was defeated")
	reset_case()
	var source = game.summon_evocation(0,"anubis","arena")
	var receipt := mage_context()
	receipt["source_evocation"] = source
	receipt["resolver_kind"] = "evocation"
	DruidicRules.sequence(game,[{"type":"damage","amount":1}],receipt,"evocation")
	await drive()
	expect(receipt.get("last_damage_source_model_type") == "evocation", "Evocation follow-up damage retains its source against Mage")
	var ev_target = game.summon_evocation(1,"nigredo","arena")
	receipt = {"game":game,"caster_id":0,"source_evocation":source,"resolver_kind":"evocation","target_evocation":ev_target,"target_model_type":"evocation","spell_target_type":"evocation"}
	game.active_effect_context = receipt
	game.processing_resolution_stack = true
	game.effect_resolver.resolve_effect({"type":"damage","amount":1},receipt)
	var damage_frame: Dictionary = game.resolution_stack.back()
	game.processing_resolution_stack = false
	game.active_effect_context = {}
	await drive()
	expect(damage_frame.event.source_model_type == "evocation" and damage_frame.event.source_evocation == source and ev_target.get_damage()==1, "Evocation follow-up damage event retains its source against Evocation")
	reset_case()
	game.active_school_ids.assign(game.school_specialization_database.keys())
	game.create_school_libraries()
	for school in game.school_libraries:
		expect(game.school_libraries[school].all(func(c):return not c.personal and not c.forgotten),"Library excludes personal/Forgotten: "+school)
	for mage in game.mage_database.mages.values():
		var personal: SpellCardState=game.spell_database.get_spell(mage.personal_spell_id)
		expect(personal!=null and personal.personal,"Personal flag present for "+mage.name)
		if personal!=null:
			expect(game.discard_to_school(personal.school_id,personal),"Personal Study discard accepted: "+mage.name)
			expect(not game.school_discards.get(personal.school_id,[]).has(personal),"Personal never enters Library discard: "+mage.name)
	print("PLAYTEST REGRESSIONS: %d checks, %d failures" % [checks,failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
