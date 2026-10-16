class_name TriggeredSpellManager
extends RefCounted


func get_triggered_spells(
	event: GameEvent,
	players: Array
) -> Array[Dictionary]:

	var triggered: Array[Dictionary] = []

	for player_index in range(players.size()):
		var player = players[player_index]

		for active_spell in player.active_spells:
			if not active_spell.active:
				continue
				
			var spell_type = active_spell.get_spell_type()

			if spell_type in event.suppressed_trigger_types:
				continue
			var trigger = active_spell.get_trigger()
			if bool(trigger.get("jinxed", false)) and (event.source_player_index < 0 or players[event.source_player_index].mage.jinxes.is_empty()):
				continue

			if trigger.is_empty():
				continue

			if trigger_matches(
				trigger,
				event,
				active_spell
			):
				triggered.append({
					"active_spell": active_spell,
					"event": event
				})

	return triggered
	
func trigger_matches(
	trigger: Dictionary,
	event: GameEvent,
	active_spell: ActiveSpellState
) -> bool:

	var trigger_type = str(
		trigger.get("type", "")
	)

	match trigger_type:
		"caster_casts_spell", "marked_mage_casts_spell":
			return event.event_type == "spell_cast_started" and event.source_player_index == (active_spell.owner_id if trigger_type == "caster_casts_spell" else active_spell.target_player_index)
		"mage_reveals_spell_type":
			return event.event_type == "spell_revealed" and event.data.get("spell_type") == trigger.get("spell_type")
		"model_enters_marked_room", "mage_enters_marked_room":
			return event.event_type in (["mage_enters_room", "evocation_enters_room"] if trigger_type == "model_enters_marked_room" else ["mage_enters_room"]) and event.target_room_id == str(active_spell.context.get("target_room_id", ""))
		"model_enters_caster_room":
			return event.event_type == "evocation_enters_room" or (event.event_type == "mage_enters_room" and event.source_player_index != active_spell.owner_id)
		"another_mage_enters_any_room":
			return event.event_type == "mage_enters_room" and event.source_player_index != active_spell.owner_id
		"caster_enters_room":
			return event.event_type == "mage_enters_room" and event.source_player_index == active_spell.owner_id
		"marked_mage_damages_caster":
			return event.event_type == "damage_inflicted" and event.amount > 0 and event.source_player_index == active_spell.target_player_index and event.target_player_index == active_spell.owner_id and event.target_model_type == "mage"
		"marked_mage_reveals_spell":
			return event.event_type == "spell_revealed" and event.source_player_index == active_spell.target_player_index
		"spell_about_to_damage_caster":
			return event.event_type == "damage_about_to_be_inflicted" and event.amount > 0 and event.action_type == "spell" and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id
		"caster_resolves_prophecy", "caster_resolves_oracle_keyword":
			return event.event_type == "oracle_keyword_resolved" and event.source_player_index == active_spell.owner_id and (trigger_type == "caster_resolves_oracle_keyword" or event.data.get("keyword") == "prophecy")
		"another_mage_suffers_last_damage":
			return event.event_type == "damage_inflicted" and event.amount > 0 and event.target_model_type == "mage" and event.target_player_index != active_spell.owner_id and bool(event.data.get("lethal", false))
		"another_model_about_to_damage_caster":
			return event.event_type == "damage_about_to_be_inflicted" and event.amount > 0 and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and is_another_model(event, active_spell.owner_id)
		"another_mage_resolves_room":
			return event.event_type == "room_effect_resolved" and event.source_player_index >= 0 and event.source_player_index != active_spell.owner_id
		"another_mage_places_instability":
			return event.event_type == "instability_placed" and event.amount > 0 and event.source_player_index >= 0 and event.source_player_index != active_spell.owner_id
		"another_mage_gains_trophy":
			return event.event_type == "trophy_gained" and event.source_player_index >= 0 and event.source_player_index != active_spell.owner_id
		"marked_mage_enters_room":
			return event.event_type == "mage_enters_room" and event.source_player_index == active_spell.target_player_index
		"owned_evocation_about_to_suffer_damage":
			return event.event_type == "damage_about_to_be_inflicted" and event.amount > 0 and event.target_evocation != null and event.target_evocation.owner_id == active_spell.owner_id
		"another_mage_about_to_damage_caster":
			return event.event_type == "damage_about_to_be_inflicted" and event.amount > 0 and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and event.source_model_type == "mage" and event.source_player_index != active_spell.owner_id
		"caster_targeted_by_physical_attack":
			return event.event_type == "damage_about_to_be_inflicted" and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and event.action_type in ["physical_attack", "evocation_attack"]
		"caster_about_to_suffer_at_least_damage":
			return event.event_type == "damage_about_to_be_inflicted" and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and event.amount >= int(trigger.get("amount", 2))
		"another_mage_enters_room":
			# The Game adds these triggers with the authoritative Room colour.
			return false
		"caster_targeted_or_about_to_suffer_spell_effect":
			# The Game supplies the affected players and the source Spell type.
			return false
		"marked_mage_places_instability":
			return event.event_type == "instability_placed" and event.amount > 0 and event.source_player_index == active_spell.target_player_index

		"another_model_inflicts_damage":
			return (
				event.event_type == "damage_inflicted"
				and is_another_model(
					event,
					active_spell.owner_id
				)
			)

		"another_model_inflicts_damage_to_caster":
			return (
				event.event_type == "damage_inflicted"
				and event.target_model_type == "mage"
				and event.target_player_index
					== active_spell.owner_id
				and is_another_model(
					event,
					active_spell.owner_id
				)
			)
		"marked_mage_inflicts_damage":
			if event.event_type != "damage_inflicted" or event.amount <= 0:
				return false

			if event.source_model_type != "mage":
				return false

			if event.source_player_index != active_spell.target_player_index:
				return false

			var allowed_action_types = trigger.get(
				"action_types",
				[]
			)

			return allowed_action_types.is_empty() or event.action_type in allowed_action_types
		
		"caster_about_to_suffer_damage":
			return (
				event.event_type == "damage_about_to_be_inflicted"
				and event.target_model_type == "mage"
				and event.target_player_index == active_spell.owner_id
			)
		"another_mage_suffers_damage":
			if event.event_type != "damage_inflicted":
				return false

			if event.target_model_type != "mage":
				return false

			# "Another Mage":
			# The Trap caster cannot be the entering Mage
			# che ha appena subito Damage.
			if event.target_player_index == active_spell.owner_id:
				return false
			return true
		
		"another_mage_casts_quick_spell":
			return (
				event.event_type == "quick_spell_cast"
				and event.source_model_type == "mage"
				and event.source_player_index >= 0
				and event.source_player_index
					!= active_spell.owner_id
			)

		"another_mage_solves_quest":
			return (
				event.event_type == "quest_solved"
				and event.source_model_type == "mage"
				and event.source_player_index
					!= active_spell.owner_id
			)
		"caster_is_defeated":
			return (
				event.event_type == "mage_defeated"
				and event.target_model_type == "mage"
				and event.target_player_index
					== active_spell.owner_id
			)

		"another_mage_is_defeated":
			return (
				event.event_type == "mage_defeated"
				and event.target_model_type == "mage"
				and event.target_player_index
					!= active_spell.owner_id
			)
		"another_mage_gains_power":
			return (
				event.event_type == "power_gained"
				and event.source_model_type == "mage"
				and event.source_player_index
					!= active_spell.owner_id
			)

		"another_mage_loses_power":
			return (
				event.event_type == "power_lost"
				and event.source_model_type == "mage"
				and event.source_player_index
					!= active_spell.owner_id
			)
		"marked_mage_gains_or_loses_power":
			if event.event_type != "power_gained" \
			and event.event_type != "power_lost":
				return false

			if event.source_model_type != "mage":
				return false

			return (
				event.source_player_index
				== active_spell.target_player_index
			)

		"marked_mage_resolves_spell_type":
			if event.event_type != "spell_effect_resolved":
				return false

			if event.source_model_type != "mage" \
			or event.source_player_index != active_spell.target_player_index:
				return false

			return str(event.data.get("spell_type", "")) == str(
				trigger.get("spell_type", "")
			)

		"marked_mage_resolves_room_effect":
			return event.event_type == "room_effect_resolved" \
				and event.source_model_type == "mage" \
				and event.source_player_index == active_spell.target_player_index

		"caster_suffers_black_rose_damage":
			return (
				event.event_type == "damage_inflicted"
				and event.source_model_type == "black_rose"
				and event.target_model_type == "mage"
				and event.target_player_index
					== active_spell.owner_id
			)
		"your_evocation_defeated_or_removed":

			if event.event_type != "evocation_defeated_or_removed":
				return false

			if event.target_evocation == null:
				return false

			return (
				event.target_player_index
				== active_spell.owner_id
			)
		"you_suffer_damage":

			if event.event_type != "damage_about_to_be_inflicted":
				return false

			if event.target_model_type != "mage":
				return false

			if event.target_player_index != active_spell.owner_id:
				return false

			return event.amount > 0
		"another_mage_places_last_instability":
			return event.event_type == "last_instability_placed" and event.source_player_index >= 0 and event.source_player_index != active_spell.owner_id
		"another_mage_inflicts_last_damage":
			return event.event_type == "damage_inflicted" and event.source_model_type == "mage" and event.source_player_index != active_spell.owner_id and event.target_model_type == "mage" and bool(event.data.get("lethal", false))
		"non_forgotten_spell_affects_caster":
			return event.event_type == "spell_effect_about_to_resolve" and active_spell.owner_id in event.data.get("targets", [])
		"another_mage_completes_or_solves_quest":
			return event.event_type in ["quest_completed", "quest_solved"] and event.source_player_index >= 0 and event.source_player_index != active_spell.owner_id
		"mage_placed_in_cell", "another_mage_placed_in_cell":
			return event.event_type == "mage_placed_in_cell" and (trigger_type == "mage_placed_in_cell" or event.source_player_index != active_spell.owner_id)
		"another_mage_inflicts_damage":
			return event.event_type == "damage_inflicted" and event.amount > 0 and event.source_model_type == "mage" and event.source_player_index != active_spell.owner_id
		"another_mage_inflicts_damage_to_caster":
			return event.event_type == "damage_about_to_be_inflicted" and event.amount > 0 and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and event.source_model_type == "mage" and event.source_player_index != active_spell.owner_id
		"evocation_inflicts_damage_to_caster":
			return event.event_type == "damage_inflicted" and event.amount > 0 and event.target_model_type == "mage" and event.target_player_index == active_spell.owner_id and event.source_model_type == "evocation" and event.source_player_index != active_spell.owner_id
		"evocation_defeated_or_removed":

			if event.event_type != "evocation_defeated_or_removed":
				return false

			return event.target_evocation != null
		_:
			print(
				"UNKNOWN TRIGGER TYPE: ",
				trigger_type
			)

			return false

func is_another_model(
	event: GameEvent,
	owner_id: int
) -> bool:

	if event.source_model_type == "mage":
		return (
			event.source_player_index
			!= owner_id
		)

	if event.source_model_type == "evocation":
		if event.source_evocation == null:
			return false

		return (
			event.source_evocation.controller_id
			!= owner_id
		)

	return false
