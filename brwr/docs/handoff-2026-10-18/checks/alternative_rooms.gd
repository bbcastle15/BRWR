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

func use_room_variant(id: String):
	for definition in game.room_database:
		if str(definition.id) == id:
			var room = game.get_room_by_id(str(definition.get("replaces", id)))
			room.setup_room(definition)
			return room
	return null

func run() -> void:
	game = await make_game(4)
	for variant in ["crypt", "crypt_of_the_saint"]:
		for dark in [false, true]:
			reset_case()
			var room = use_room_variant(variant)
			expect(room != null and room.room_id == "crypt", "Variant keeps Crypt identity: " + variant)
			locate(0, "crypt")
			var quest := QuestState.new(game.quest_database.get_quest("cinder_star"), 0)
			game.players[0].active_quests.append(quest)
			await cast("mass_production", dark)
			expect(quest.completed and game.players[0].completed_quests.has(quest), "Mass Production completes Cinder Star: %s %s" % [variant, dark])
	reset_case()
	var task: Dictionary = game.quest_database.get_quest("cinder_star").task
	for type in ["combat", "contingency", "protection", "trap"]:
		expect(game.quest_manager._task_matches(game, 0, task, {"type":"spell_resolved","caster_room_id":"crypt","spell_type":type,"spell_element":"magic"}) == (type in ["combat","contingency"]), "Cinder Star checks spell type: " + type)
	expect(not game.quest_manager._task_matches(game, 0, task, {"type":"spell_resolved","caster_room_id":"arena","spell_type":"combat","spell_element":"fire"}), "Cinder Star still requires Crypt")
	# All replacement definitions continue to use their base identity for Quest checks.
	for definition in game.room_database:
		if not definition.has("replaces") or not bool(definition.get("playable", true)): continue
		var room = use_room_variant(str(definition.id))
		expect(room != null and room.room_id == str(definition.replaces), "Base identity: " + str(definition.id))
		if room != null:
			for key in ["room_id", "in_room_id"]:
				var qt := {"trigger":"spell_resolved"}
				qt[key] = str(definition.replaces)
				expect(game.quest_manager._task_matches(game,0,qt,{"type":"spell_resolved","room_id":room.room_id,"caster_room_id":room.room_id}), "Quest equivalent: " + str(definition.id) + "/" + key)
	reset_case()
	var own = game.summon_evocation(0,"nigredo","arena")
	var equipment = game.summon_evocation(0,"talos_corset","arena")
	var enemy_equipment = game.summon_evocation(1,"talos_corset","arena")
	var foe = game.summon_evocation(1,"nigredo","arena")
	var ctx := {"game":game,"caster_id":0,"caster_room_id":"arena"}
	for id in ["dark_path","ethereal_tentacles","void_wandering","gluttony","misfortune","pyoderma","vigorous_infusion","dracos_skin"]:
		var card: SpellCardState = game.spell_database.get_spell(id)
		for dark in [false,true]:
			var side: Dictionary = card.get_side(dark)
			if str(side.target) != "model": continue
			var options: Array = game._spell_primary_target_options(0,side)
			expect(not options.any(func(o): return o.value.get("evocation") in [equipment,enemy_equipment]), "Model Spell excludes Equipment: %s %s" % [id,dark])
	var models := ForgottenRules.models(game,ctx)
	expect(not models.any(func(o):return o.value.get("evocation") in [equipment,enemy_equipment]), "Shared Model choices exclude Equipment")
	expect(models.any(func(o):return o.value.get("evocation") == own) and models.any(func(o):return o.value.get("evocation") == foe), "Real Evocations remain Model targets")
	var targets := ForgottenRules.models(game,ctx,"evocation")
	expect(targets.any(func(o):return o.value.get("evocation") == equipment), "Owner can still target Equipment as Evocation")
	expect(not targets.any(func(o):return o.value.get("evocation") == enemy_equipment), "Cannot target opponent Equipment as Evocation")
	var moved := SchoolEffects.model_options(game,{"owner":"self","movable":true},ctx)
	expect(moved.size()==1 and moved[0].value.evocation==own, "Eldritch Tentacle excludes Equipment when placing owned Evocation")
	var quest_models: Array = game._quest_model_choice_options(0, {"target":"model","range":"*"})
	expect(not quest_models.any(func(o):return o.value.get("evocation") in [equipment,enemy_equipment]), "Quest Model choices exclude Equipment")
	expect(not game.move_evocation_to_room_id(equipment,"crypt",99), "Authoritative movement rejects Equipment")
	expect(not game.place_evocation_in_room_direct(equipment,"crypt"), "Authoritative placement rejects Equipment")
	expect(equipment.room_id=="arena", "Equipment remains assigned to owner location")
	game.refresh_model_tokens()
	expect(not game.evocation_tokens.has(equipment.get_instance_id()) and not game.evocation_tokens.has(enemy_equipment.get_instance_id()), "Equipment has no Lodge token")
	expect(game.evocation_tokens.has(own.get_instance_id()) and game.evocation_tokens.has(foe.get_instance_id()), "Evocation map tokens preserved")
	game.place_mage_in_room_direct(0,"crypt")
	await drive()
	EquipmentRules.sync(game)
	expect(equipment.room_id=="crypt", "Equipment continues to follow owning Mage")
	for rebuilt in [false,true]:
		reset_case()
		var room = use_room_variant("crusaders_summoner_room")
		room.flipped = rebuilt
		locate(0,"summoner_room")
		own = game.summon_evocation(0,"nigredo","summoner_room")
		foe = game.summon_evocation(1,"nigredo","summoner_room")
		var distant = game.summon_evocation(2,"nigredo","summoner_room")
		for id in game.room_id_by_coord.values():
			if not game.is_room_within_effect_range("summoner_room",id,1): distant.room_id=id; break
		expect(game.activate_room(0,"summoner_room"), "Crusaders Room activation queued")
		await process_frame
		game.process_resolution_stack()
		expect(game.waiting_for_player_input, "Crusaders Room awaits target")
		var choices: Array = game.pending_input.get("options",[])
		expect(choices.size()==1 and choices[0].owner_id==1, "Crusaders targets only opponent Evocation within 1")
		await drive()
		expect(own.get_damage()==0, "Crusaders Room never damages own Evocation")
		expect(foe.get_damage()==2 if not rebuilt else not game.is_evocation_in_play(foe), "Crusaders Room inflicts printed damage: %s" % rebuilt)
		expect(distant.get_damage()==0, "Distant Evocation unaffected")
	reset_case()
	var room = use_room_variant("crusaders_summoner_room")
	locate(0,"summoner_room")
	own=game.summon_evocation(0,"nigredo","summoner_room")
	game.activate_room(0,"summoner_room")
	await drive()
	expect(decisions.is_empty() and own.get_damage()==0, "No opponent target: Room resolves without forcing own Evocation")
	reset_case()
	var library = use_room_variant("bibliotheca_of_the_order")
	locate(0,"bibliotheca")
	var spell: SpellCardState = game.spell_database.get_spell("mass_production")
	var ready := ReadySpellState.new(spell,false)
	game.players[0].ready_spells.assign([ready])
	game._sync_player_board_prepared_spells(0)
	game.players[0].grimoire.assign([game.spell_database.get_spell("hammerfall"),game.spell_database.get_spell("liquid_fire")])
	game.players[0].memories.clear()
	game.activate_room(0,"bibliotheca")
	await process_frame
	expect(game.waiting_for_player_input and game.pending_input.choice_kind=="room_payment", "Bibliotheca asks for prepared spell discard")
	expect(game.pending_input.options[0].slot_id=="I" and game.pending_input.options[0].board_player_index==0, "Payment choice addresses original private prepared slot")
	expect(game.players[0].ready_spells.has(ready), "Request alone does not discard")
	await drive()
	expect(game.players[0].ready_spells.is_empty() and game.players[0].memories.has(spell), "Only selected prepared spell is discarded")
	expect(game.players[0].hand.size()==2, "Bibliotheca draws two cards after cost")
	print("ALTERNATIVE ROOM REGRESSIONS: %d checks, %d failures" % [checks,failures.size()])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
