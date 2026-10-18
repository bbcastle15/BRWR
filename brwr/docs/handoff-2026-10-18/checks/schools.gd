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
	create_timer(60).timeout.connect(func(): push_error("Famine check timeout"); quit(2))

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
	game.players[1].mage.damage_cubes.assign([2,2,2,3])
	preferred["chaos_branch"]=1
	await cast("cruelty",false)
	expect(game.players[1].mage.damage_cubes==[0,0,0,3],"Cruelty converts exactly the chosen three damage cubes in place")
	expect(decisions.any(func(d):return d.choice_kind=="convert_damage_cubes"),"Conversion requests clickable damage cubes")
	reset_case()
	var foe=game.summon_evocation(1,"nigredo","arena")
	foe.damage_cubes.assign([2,2,2])
	preferred["chaos_branch"]=1
	game.cast_ready_spell_state(0,ReadySpellState.new(game.spell_database.get_spell("cruelty"),false),{"target_evocation":foe,"target_model_type":"evocation"})
	await drive()
	expect(foe.damage_cubes==[0,0,0],"Cruelty converts selected Evocation damage")
	reset_case()
	await cast("persecution",false,0)
	await cast("deadly_bolt",false,1,0)
	expect(game.players[0].mage.get_damage()==0,"Persecution prevents three incoming Spell damage")
	expect(game.players[1].mage.get_damage()==3,"Persecution reflects exactly the prevented damage to the caster")
	reset_case()
	var victim=game.summon_evocation(1,"pupa","arena")
	foe=game.summon_evocation(2,"nigredo","arena")
	game.cast_ready_spell_state(0,ReadySpellState.new(game.spell_database.get_spell("blacksmiths_chant"),false),{"target_evocation":victim,"target_model_type":"evocation"})
	await drive()
	expect(not game.is_evocation_in_play(victim),"Blacksmith removes the chosen Evocation")
	expect(foe.get_damage()==0,"Blacksmith Light does not damage nearby Evocations")
	expect(game.players[0].mage.get_damage()==0 and game.players[1].mage.get_damage()==2,"Blacksmith Light affects other Mages only")
	reset_case()
	var adjacent: String=game._beta_adjacent_room_ids("arena")[0]
	locate(2,adjacent)
	foe=game.summon_evocation(1,"nigredo","arena")
	chosen_room=adjacent
	game.cast_ready_spell_state(0,ReadySpellState.new(game.spell_database.get_spell("mars_glory"),false),{"target_evocation":foe,"target_model_type":"evocation"})
	await drive()
	expect(foe.upgrades.has("warscratch"),"Mars Glory assigns Warscratch")
	expect(game.players[2].mage.get_damage()==game.get_evocation_effective_strength(foe),"Mars Glory inflicts upgraded Strength in chosen Room")
	expect(game.players[1].mage.get_damage()==0,"Mars Glory does not affect every Room in range")
	reset_case()
	var blade: SpellCardState=game.spell_database.get_spell("hardened_blades")
	game.players[0].grimoire.assign([blade])
	game.players[0].hand.clear()
	await cast("mechanical_archive",true)
	expect(game.players[0].hand.has(blade),"Mechanical Archive finds Equipment Summon keyword")
	reset_case()
	var quest: QuestState
	for definition in game.quest_database.quests.values():
		if definition.id.contains("summoner_wizard"):
			quest=QuestState.new(definition,0); break
	expect(quest!=null,"Summoner Wizard exists for regression")
	if quest!=null:game.players[0].active_quests.append(quest)
	await cast("bloodline",true)
	expect(quest.progress==1,"Bloodline's summon choice progresses Summoner Wizard once")
	reset_case()
	var ready_card: SpellCardState=game.spell_database.get_spell("persecution")
	game.players[0].hand.assign([ready_card])
	game.players[0].add_ready_spell(ready_card,false)
	game._set_player_board_spell_slot(0,"II",ready_card,false,"prepared")
	await cast("branding",false)
	expect(game.players[0].ready_spells.is_empty(),"Branding removes the chosen reaction from Ready")
	expect(game.players[0].active_spells.any(func(a):return a.spell==ready_card),"Branding arms the Protection")
	expect(not game.get_player_board_spell_slot_data(0,"II",1).get("can_inspect",true),"Armed Protection stays private until triggered")
	await cast("deadly_bolt",false,1,0)
	expect(game.players[0].mage.get_damage()==0,"Branding-armed Protection resolves normally")
	expect(game.get_player_board_spell_slot_data(0,"II",1).get("can_inspect",false),"Triggered Protection becomes public in its original slot")
	reset_case()
	var board_events: Array=game.event_database.events.values().filter(func(e):return not e.is_instant())
	game.active_events=[board_events[0],board_events[1],board_events[2]]
	var hand_count: int=game.players[0].hand.size()
	await cast("thirst_for_knowledge",false)
	expect(ForgottenRules.event_count(game)==0,"Thirst for Knowledge pays all three Events")
	expect(game.players[0].hand.size()==hand_count+1 and game.players[0].hand.back().forgotten,"Thirst for Knowledge draws a Forgotten Spell after payment")
	reset_case()
	foe=game.summon_evocation(1,"nigredo","arena")
	var nightmare_context: Dictionary=mage_context()
	await effects([{"type":"assign_nightmare","evocation_id":"umbra"},{"type":"activate_last_nightmare"}],nightmare_context)
	expect(game.players[1].mage.get_damage()==1,"Assigned Umbra attacks its Mage")
	expect(foe.get_damage()==1,"Umbra damages the Evocation in its assigned slot")
	expect(game.players[1].has_free_evocation_slot(),"Nightmares do not occupy ordinary Evocation slots")
	reset_case()
	var bow=game.summon_evocation(0,"eros_bow","arena")
	game.players[0].available_physical_actions=2
	var actions: Array=EquipmentRules.actions(game,0)
	expect(actions.size()==1,"Bow exposes its Equipment action")
	expect(EquipmentRules.perform(game,0,"eros_bow",str(actions[0].action.action_id)),"Bow action starts")
	await drive()
	expect(game.players[0].available_physical_actions==1,"Equipment action exhausts one physical token")
	expect(game.players[1].mage.get_damage()==1 and game.players[0].power==11 and game.players[1].power==9,"Bow deals one damage then steals one Power")
	reset_case()
	var pest=game.summon_evocation(0,"pestis","arena")
	var second=game.summon_evocation(0,"pestis",adjacent)
	game.summon_evocation(0,"tartarus_axe","arena")
	PestilenceRules.assign(game,0,1,2)
	ready_card=game.spell_database.get_spell("persecution")
	game.players[0].hand.assign([ready_card,game.spell_database.get_spell("deadly_bolt")])
	game.players[0].add_ready_spell(ready_card,false)
	game._set_player_board_spell_slot(0,"I",ready_card,false,"prepared")
	var state: Dictionary=load("res://network_projection.gd").build(game,1)
	expect(not state.players[0].has("hand"),"Remote snapshot hides another player's Hand")
	expect(not state.slots[0]["I"].get("can_inspect",true) and not state.slots[0]["I"].has("id"),"Remote snapshot hides prepared Spell identity")
	var client=await make_game(4)
	load("res://network_projection.gd").apply(client,state)
	expect(client.players[1].mage.infectio_tokens==[0,0],"Remote client receives Infectio owners")
	expect(client.players[0].evocations.size()==3 and client.players[0].has_free_evocation_slot(),"Remote Pestis do not consume normal slots")
	expect(client.players[0].evocations[0].board_number!=client.players[0].evocations[1].board_number,"Remote Pestis keep distinct identities")
	expect(client.get_evocation_stored_owner_cube_count(client.players[0].evocations[0])==1,"Remote Pestis shows reserved owner cube")
	expect(client.players[0].get_mage_strength()==game.players[0].get_mage_strength(),"Remote Equipment uses authoritative definition and stat bonus")
	expect(client.player_boards[1].get_node("DestinyTokens").get_child_count()==2,"Remote board shows Infectio tokens")
	client.queue_free()
	game.queue_free()
	await process_frame
	print("SCHOOL INTEGRATION: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
