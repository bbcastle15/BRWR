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
			if event.event_type != "damage_inflicted":
				return false

			if event.source_model_type != "mage":
				return false

			if event.source_player_index != active_spell.target_player_index:
				return false

			var allowed_action_types = trigger.get(
				"action_types",
				[]
			)

			return event.action_type in allowed_action_types
		
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
			# il caster della Trap non può essere il Mage
			# che ha appena subito Damage.
			if event.target_player_index == active_spell.owner_id:
				return false
			return true
		
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
