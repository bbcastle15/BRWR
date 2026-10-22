class_name EffectResolver
extends RefCounted

# =============================================================================
# EFFECT RESOLVER - CONSOLIDATED VERSION
# =============================================================================
# Existing JSON effect names are preserved, but similar effects are routed
# through shared handlers instead of having one large function per card.
# Game.gd only needs resolve_effects(), so this remains a drop-in replacement
# for the current game architecture.
# =============================================================================


# =============================================================================
# PUBLIC API
# =============================================================================

func resolve_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	context.erase("effect_resolution_error")
	var effect_type = str(effect.get("type", ""))
	var game = context.get("game")
	if game != null:
		ForgottenPassives.prepare_context(game, context)
		var target_ev: EvocationState = context.get("target_evocation")
		if target_ev != null and str(context.get("resolver_kind", "spell")) == "spell" and not ForgottenEvocations.ability(game, target_ev, "ignore_spell_effects").is_empty():
			return true
	if bool(effect.get("only_on_trigger", false)) and context.get("trigger_event") == null:
		return true
	if bool(effect.get("only_on_initial_cast", false)) and context.get("trigger_event") != null:
		return true
	if _caput_direct_target_is_ignored(context):
		return true
	if effect_type in DeathEffectResolver.TYPES:
		return DeathEffectResolver.resolve(effect, context)
	if effect_type in DruidicRules.EFFECT_TYPES:
		return DruidicRules.resolve(effect, context)
	if effect_type in ForgottenRules.EFFECT_TYPES:
		return ForgottenRules.resolve(effect, context)
	if effect_type in PestilenceRules.TYPES:
		return PestilenceRules.resolve(effect, context)
	if effect_type in OracleRules.TYPES:
		return OracleRules.resolve(effect, context)
	if effect_type in SchoolEffects.TYPES:
		return SchoolEffects.resolve(effect, context)
	if effect_type in FamineRules.EFFECT_TYPES:
		return FamineRules.resolve(effect, context)

	match effect_type:
		# Core model effects.
		"damage":
			return _resolve_damage(effect, context)
		"heal":
			return _resolve_heal(effect, context)
		"gain_power", "lose_power":
			return _resolve_power(effect, context, effect_type)
		"place_instability":
			return _resolve_place_instability(effect, context)
		"remove_instability":
			return _resolve_remove_instability(effect, context)
		"place_instability_from_context":
			return _resolve_place_instability_from_context(effect, context)
		"pain":
			return _resolve_pain(effect, context)
		"convert_damage", "convert_damage_on_caster":
			return _resolve_convert_damage(effect, context, effect_type)
		"convert_instability":
			return _resolve_convert_instability(effect, context)
		"choose_one":
			return _resolve_choose_one(effect, context)
		"place_vastum":
			return _resolve_place_vastum(effect, context)
		"remove_vastum":
			return _resolve_remove_vastum(effect, context)
		"remove_vastum_from_lodge":
			return _resolve_remove_vastum_from_lodge(effect, context)
		"chaos":
			return _resolve_chaos(effect, context)
		"damage_equal_vastum_count":
			return _resolve_damage_equal_vastum_count(effect, context)
		"move_target_up_to":
			return _resolve_move_target_up_to(effect, context)
		"memory_to_top_grimoire":
			return _resolve_memory_to_top_grimoire(effect, context)
		"search_grimoire_to_top":
			return _resolve_search_grimoire_to_top(effect, context)
		"place_caster_in_target_room":
			return _resolve_place_caster_in_target_room(effect, context)
		"place_target_in_vastum_room":
			return _resolve_place_target_in_vastum_room(effect, context)
		"place_target_in_caster_room":
			return _resolve_place_target_in_caster_room(effect, context)
		"place_target_in_any_room":
			return _resolve_place_target_in_any_room(effect, context)
		"place_caster_in_vastum_room":
			return _resolve_place_caster_in_vastum_room(effect, context)
		"lose_caster_power":
			return _resolve_lose_caster_power(effect, context)
		"convert_damage_each_other_mage":
			return _resolve_convert_damage_each_other_mage(effect, context)
		"damage_within_distance":
			return _resolve_damage_within_distance_effect(effect, context)
		"place_instability_per_damaged_model":
			return _resolve_place_instability_per_damaged_model(effect, context)

		# Quest / card-zone effects.
		"return_revealed_spell_to_hand":
			return _resolve_return_revealed_spell_to_hand(effect, context)
		"search_grimoire_to_hand":
			return _resolve_search_grimoire_to_hand(effect, context)
		"draw_library":
			return _resolve_draw_library(effect, context)
		"take_crown":
			return _resolve_take_crown(effect, context)
		"draw_grimoire_or_heal":
			return _resolve_draw_grimoire_or_heal(effect, context)
		"draw_grimoire":
			return _resolve_draw_grimoire(effect, context)
		"draw_quest":
			return _resolve_draw_quest(effect, context)
		"draw_forgotten":
			return _resolve_draw_forgotten(effect, context)
		"swap_with_target_mage_optional":
			return _resolve_swap_with_target_mage_optional(effect, context)
		"draw_event_optional_gain_power":
			return _resolve_draw_event_optional_gain_power(effect, context)
		"gain_power_if_no_damage":
			return _resolve_gain_power_if_no_damage(effect, context)
		"heal_all_damage":
			return _resolve_heal_all_damage(effect, context)
		"draw_event_then_damage":
			return _resolve_draw_event_then_damage(effect, context)
		"damage_all_models_lodge":
			return _resolve_damage_all_models_lodge(effect, context)
		"place_target_mage_then_damage":
			return _resolve_place_target_mage_then_damage(effect, context)
		"shuffle_memories_into_grimoire_then_draw":
			return _resolve_shuffle_memories_into_grimoire_then_draw(effect, context)
		"summon_non_forgotten_evocation_choice":
			return _resolve_summon_non_forgotten_evocation_choice(effect, context)
		"damage_or_place_instability":
			return _resolve_damage_or_place_instability(effect, context)
		"complete_owned_quest_choice":
			return _resolve_complete_owned_quest_choice(effect, context)
		"black_rose_lose_power_or_target_mage_lose_power":
			return _resolve_black_rose_or_mage_power_loss(effect, context)
		"refresh_physical_action_token":
			return _resolve_refresh_physical_action_token(effect, context)
		"give_forgotten_to_target":
			return _resolve_give_forgotten_to_target(effect, context)
		"draw_three_forgotten_keep_one":
			return _resolve_draw_three_forgotten_keep_one(effect, context)
		"activate_evocation_or_summon_nigredo":
			return _resolve_activate_evocation_or_summon_nigredo(effect, context)
		"steal_power_from_up_to_mages":
			return _resolve_steal_power_from_up_to_mages(effect, context)

		# Effects whose amount is derived from another game value.
		"damage_per_black_rose_damage", \
		"damage_per_self_damage", \
		"damage_secondary_mage_per_self_damage", \
		"gain_power_per_black_rose_damage", \
		"place_instability_at_defeated_mage_room_per_self_damage", \
		"place_instability_per_black_rose_damage_on_effect_damaged_models", \
		"place_instability_per_self_black_rose_damage", \
		"damage_per_revealed_active_element", \
		"place_instability_per_revealed_active_element":
			return _resolve_scaled_effect(effect, context, effect_type)

		# Summon family.
		"summon_evocation", \
		"summon_evocation_at_triggering_model", \
		"summon_same_evocation_as_trigger", \
		"summon_evocation_from_deck", \
		"summon_evocation_at_removed_evocation":
			return _resolve_summon_effect(effect, context, effect_type)
		"summon_evocations_distinct_rooms":
			return _resolve_summon_evocations_distinct_rooms(effect, context)

		# Removal family.
		"remove_target_evocation", \
		"remove_owned_evocation", \
		"remove_evocation_with_max_health":
			return _resolve_remove_evocation_effect(effect, context, effect_type)

		# Activation family.
		"activate_summoned_evocation", \
		"activate_owned_evocation", \
		"activate_target_evocation", \
		"activate_target_evocation_under_control":
			return _resolve_activation_effect(effect, context, effect_type)
		"activate_distinct_summoned_evocations":
			return _resolve_activate_distinct_summoned_evocations(effect, context)

		# Damage variants sharing the same low-level primitives.
		"damage_triggering_model", \
		"damage_triggering_model_from_trigger_damage", \
		"damage_from_evocation", \
		"damage_all_target_owner_evocations", \
		"damage_marked_mage", \
		"pain_from_trigger_damage", \
		"damage_all_models_of_type", \
		"damage_models_damaged_by_effect":
			return _resolve_damage_variant(effect, context, effect_type)

		# Geomancy: Fortuna / Cauda / Carcer / Conjunctio / Lifeline.
		"discard_active_events":
			return _resolve_discard_active_events(effect, context)
		"gain_power_from_context":
			return _resolve_gain_power_from_context(effect, context)
		"conditional_payment":
			return _resolve_conditional_payment(effect, context)
		"discard_spell":
			return _resolve_discard_spell(effect, context)
		"discard_unsolved_quest":
			return _resolve_discard_unsolved_quest(effect, context)
		"discard_solved_quest":
			return _resolve_discard_solved_quest(effect, context)
		"draw_from_memories":
			return _resolve_draw_from_memories(effect, context)
		"draw_from_library":
			return _resolve_draw_from_library(effect, context)
		"place_self_in_room":
			return _resolve_place_self_in_room(effect, context)
		"place_self_in_target_room":
			return _resolve_place_self_in_target_room(effect, context)
		"activate_evocation_owned_by_target_under_control":
			return _resolve_activate_evocation_owned_by_target_under_control(effect, context)
		"heal_from_context":
			return _resolve_heal_from_context(effect, context)

		# Trigger / flow control.
		"conditional":
			return _resolve_conditional(effect, context)
		"geoform":
			return _resolve_geoform(effect, context)
		"redirect_damage_to_evocation":
			return _resolve_redirect_damage(effect, context)
		"gain_power_from_defeating_model":
			return _resolve_gain_power_from_defeat(effect, context)
		"ignore_trigger_damage":
			return _resolve_ignore_trigger_damage(effect, context)
		"ignore_trigger_spell_effect":
			return _resolve_ignore_trigger_spell_effect(effect, context)

		# Targeting / movement / Room interaction.
		"modify_spell_target":
			return _resolve_modify_spell_target(effect, context)
		"set_target_room_from_target_evocation":
			return resolve_set_target_room_from_target_evocation(
				effect,
				context
			)
		"set_target_room_from_triggering_mage":
			return resolve_set_target_room_from_triggering_mage(
				effect,
				context
			)
		"set_target_mage_from_triggering_mage":
			return resolve_set_target_mage_from_triggering_mage(
				effect,
				context
			)
		"steal_power":
			return _resolve_steal_power(effect, context)
		"activate_target_room":
			return _resolve_activate_target_room(effect, context)
		"move_one_model_damaged_by_effect":
			return _resolve_move_damaged_model(effect, context)
		"damage_rooms_in_range_from_target":
			return _resolve_damage_rooms_in_range_from_target(effect, context)
		"move_one_mage_in_target_room":
			return _resolve_move_one_mage_in_target_room(effect, context)
		"move_model_near_target_room":
			return _resolve_move_model_near_target_room(effect, context)
		"activate_room_from_owned_evocation":
			return _resolve_activate_room_from_evocation(effect, context)

		# Multi-step composite effects that still need one dedicated handler.
		"remove_owned_evocation_and_damage_around":
			return _resolve_remove_and_damage_around(effect, context)
		"fountain_construct_or_nigredo", "silver_defeat_choice":
			return _resolve_choice_effect(effect, context, effect_type)
		"heal_target_evocation":
			return _resolve_heal_target_evocation(effect, context)
		"next_activation_strength_bonus":
			return _resolve_next_activation_strength_bonus(effect, context)
		"activate_owned_evocation_then_black_rose_damage":
			return _resolve_activate_then_black_rose_damage(effect, context)

		_:
			context["effect_resolution_error"] = "unknown_effect_type"
			print("UNKNOWN EFFECT TYPE: ", effect_type)
			return false


func resolve_effects(
	effects: Array,
	context: Dictionary
) -> bool:

	for effect in effects:
		if not resolve_effect(effect, context):
			return false

	return true


# =============================================================================
# COMMON HELPERS
# =============================================================================

func _game(context: Dictionary):
	return context.get("game")


func _caster(context: Dictionary) -> int:
	return int(context.get("caster_id", -1))


func _valid_player(game, player_index: int) -> bool:
	return (
		game != null
		and player_index >= 0
		and player_index < game.players.size()
	)


func _target_type(context: Dictionary) -> String:
	var result = str(context.get("spell_target_type", ""))
	if result == "model" and not bool(context.get("target_is_dummy", false)):
		if context.get("target_evocation") != null: return "evocation"
		if int(context.get("target_player_index", -1)) >= 0: return "mage"

	# Compatibility with old direct tests.
	if result == "" \
	and context.has("target_player_index"):
		result = "mage"

	return result


func _is_dummy_target(context: Dictionary) -> bool:
	return (
		bool(context.get("target_is_dummy", false))
		or str(context.get("target_model_type", "")) == "dummy"
	)


func _target_room(context: Dictionary) -> String:
	return str(
		context.get(
			"target_room_id",
			context.get("room_id", "")
		)
	)


func _suppressed_triggers(effect: Dictionary) -> Array[String]:
	var result: Array[String] = []

	for trigger_type in effect.get("suppress_triggers", []):
		result.append(str(trigger_type))

	return result


func _scaled_amount(
	source_value: int,
	effect: Dictionary,
	per_step_key: String,
	default_step: int = 1,
	default_per_step: int = 1,
	default_max: int = 999
) -> int:

	var step = int(effect.get("step", default_step))
	if step <= 0:
		return -1

	var per_step = int(
		effect.get(per_step_key, default_per_step)
	)
	var cap = int(effect.get("max", default_max))

	return min(
		int(source_value / step) * per_step,
		cap
	)


func _revealed_element_count(
	game,
	caster_id: int,
	element: String
) -> int:

	if not _valid_player(game, caster_id) \
	or element == "":
		return -1

	var counts = game.get_revealed_element_counts(caster_id)

	return (
		int(counts.get(element, 0))
		+ int(counts.get("all", 0))
	)


# =============================================================================
# DAMAGE / MODEL PRIMITIVES
# =============================================================================

func _damage_mage(
	game,
	attacker_id: int,
	player_index: int,
	amount: int,
	action_type: String = "spell",
	suppressed: Array[String] = []
) -> int:

	if not _valid_player(game, player_index):
		return 0

	if attacker_id >= 0 and attacker_id == player_index:
		return 0
	if DeathEffectResolver.ignores(game.active_effect_context, player_index):
		return 0
	if action_type == "spell" and game.active_effect_context.get("resolver_kind") == "physical":
		action_type = "physical"
	var source: EvocationState = game.active_effect_context.get("source_evocation") if game.active_effect_context.get("resolver_kind") == "evocation" else null
	if source != null:
		action_type = "evocation_effect"

	return game.deal_damage(
		attacker_id,
		player_index,
		amount,
		action_type,
		suppressed,
		source
	)


func _damage_evocation(
	game,
	attacker_id: int,
	evocation,
	amount: int,
	suppressed: Array[String] = []
) -> int:

	if game == null or evocation == null:
		return 0

	if str(game.active_effect_context.get("spell_target_type", "")) in ["room", "area"] and not ForgottenEvocations.ability(game, evocation, "immune_room_damage").is_empty():
		return 0
	var controller_id: int = int(evocation.controller_id)
	if controller_id < 0:
		controller_id = int(evocation.owner_id)

	if attacker_id >= 0 and controller_id == attacker_id:
		return 0

	return game.deal_damage_to_evocation(
		attacker_id,
		evocation,
		amount,
		suppressed,
		"evocation_effect" if game.active_effect_context.get("resolver_kind") == "evocation" else ("spell" if game.active_effect_context.get("resolver_kind") == "spell" else ""),
		"evocation" if game.active_effect_context.get("resolver_kind") == "evocation" else "mage",
		game.active_effect_context.get("source_evocation") if game.active_effect_context.get("resolver_kind") == "evocation" else null
	)


func register_damaged_model(
	context: Dictionary,
	model_data: Dictionary
):

	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)
	var model_type = str(model_data.get("type", ""))

	for existing in damaged_models:
		if str(existing.get("type", "")) != model_type:
			continue

		if model_type == "mage" \
		and int(existing.get("player_index", -1)) == int(
			model_data.get("player_index", -1)
		):
			return

		if model_type == "evocation" \
		and existing.get("evocation") == model_data.get("evocation"):
			return

	damaged_models.append(model_data)
	context["models_damaged_by_effect"] = damaged_models


func _record_mage_damage(
	context: Dictionary,
	game,
	player_index: int,
	damage_dealt: int,
	room_override: String = ""
):

	context["last_damage_dealt"] = damage_dealt
	context["last_damage_target_player_index"] = player_index
	context["last_damage_defeated_target"] = (
		game.players[player_index].mage.is_defeated()
	)

	if damage_dealt <= 0:
		return

	context["last_damaged_model_type"] = "mage"
	context["last_damaged_player_index"] = player_index

	var room_id = room_override
	if room_id == "":
		room_id = game.players[player_index].mage.room_id

	register_damaged_model(
		context,
		{
			"type": "mage",
			"player_index": player_index,
			"room_id": room_id
		}
	)


func _record_evocation_damage(
	context: Dictionary,
	evocation,
	damage_dealt: int,
	room_override: String = ""
):

	context["last_damage_dealt"] = damage_dealt

	if damage_dealt <= 0:
		return

	context["last_damaged_model_type"] = "evocation"
	context["last_damaged_evocation"] = evocation

	var room_id = room_override
	if room_id == "":
		room_id = str(evocation.room_id)

	register_damaged_model(
		context,
		{
			"type": "evocation",
			"evocation": evocation,
			"room_id": room_id
		}
	)


func _damage_trigger_model(
	game,
	caster_id: int,
	amount: int,
	context: Dictionary
) -> bool:

	match str(context.get("triggering_model_type", "")):
		"mage":
			var player_index = int(
				context.get("triggering_player_index", -1)
			)

			if not _valid_player(game, player_index):
				return false

			# Original trigger retaliation used an empty action_type.
			game.deal_damage(
				caster_id,
				player_index,
				amount
			)
			return true

		"evocation":
			var evocation = context.get("triggering_evocation")
			if evocation == null:
				return false

			_damage_evocation(
				game,
				caster_id,
				evocation,
				amount
			)
			return true

		_:
			print(
				"Unknown triggering model type: ",
				context.get("triggering_model_type", "")
			)
			return false


func _damage_within_distance(
	game,
	caster_id: int,
	origin_room_id: String,
	distance: int,
	amount: int,
	context: Dictionary,
	suppressed: Array[String] = []
) -> bool:

	var origin_coord = game.room_id_to_coord(origin_room_id)
	if origin_coord == Vector2i(9999, 9999):
		return false

	for player_index in range(game.players.size()):
		var mage = game.players[player_index].mage

		if mage.in_cell:
			continue

		var coord = game.room_id_to_coord(mage.room_id)
		if coord == Vector2i(9999, 9999):
			continue

		# BRWR distances are maximum distances: 0..N.
		if game.get_hex_distance(origin_coord, coord) > distance:
			continue

		var dealt = _damage_mage(
			game,
			caster_id,
			player_index,
			amount,
			"spell",
			suppressed
		)

		if dealt > 0:
			register_damaged_model(
				context,
				{
					"type": "mage",
					"player_index": player_index
				}
			)

	for player in game.players:
		var snapshot = player.evocations.duplicate()

		for evocation in snapshot:
			if evocation == null or evocation.is_defeated():
				continue

			var coord = game.room_id_to_coord(evocation.room_id)
			if coord == Vector2i(9999, 9999):
				continue

			if game.get_hex_distance(origin_coord, coord) > distance:
				continue

			var dealt = _damage_evocation(
				game,
				caster_id,
				evocation,
				amount,
				suppressed
			)

			if dealt > 0:
				register_damaged_model(
					context,
					{
						"type": "evocation",
						"evocation": evocation
					}
				)

	return true


# =============================================================================
# EVOCATION PRIMITIVES
# =============================================================================

func _evocation_in_play(game, evocation) -> bool:
	if game == null or evocation == null:
		return false

	for player in game.players:
		if player.evocations.has(evocation):
			return true

	return false


func _evocation_matches(
	game,
	evocation,
	filters: Dictionary
) -> bool:

	if evocation == null:
		return false

	if bool(filters.get("in_play", true)) \
	and not _evocation_in_play(game, evocation):
		return false

	if bool(filters.get("alive", true)) \
	and evocation.is_defeated():
		return false

	if filters.has("owner_id") \
	and evocation.owner_id != int(filters["owner_id"]):
		return false

	var archetype = str(filters.get("archetype", ""))
	if archetype != "" \
	and str(evocation.archetype) != archetype:
		return false

	var room_id = str(filters.get("room_id", ""))
	if room_id != "" \
	and str(evocation.room_id) != room_id:
		return false

	return true


func _select_evocation(
	game,
	preferred,
	filters: Dictionary,
	auto_select: bool = true
):

	if preferred != null:
		if _evocation_matches(game, preferred, filters):
			return preferred
		return null

	if not auto_select:
		return null

	for player in game.players:
		for evocation in player.evocations:
			if _evocation_matches(game, evocation, filters):
				return evocation

	return null


func _activate_evocation(
	evocation,
	controller_id: int,
	context: Dictionary,
	strength_bonus: int = 0
) -> bool:

	if evocation == null:
		return false

	if evocation.is_defeated():
		return false

	var game = _game(
		context
	)

	if game == null:
		return false

	return game.activate_evocation(
		evocation,
		controller_id,
		context,
		strength_bonus
	)


func _summon(
	game,
	caster_id: int,
	evocation_id: String,
	room_id: String,
	context: Dictionary
):

	if not _valid_player(game, caster_id) \
	or evocation_id == "" \
	or room_id == "":
		return null

	var summoned = game.summon_evocation_for_effect(
		caster_id,
		evocation_id,
		room_id,
		context
	)

	if summoned != null:
		context["last_summoned_evocation"] = summoned
		context["effect_summoned_evocation"] = true

	return summoned


func _remove_evocation(
	game,
	evocation,
	context: Dictionary,
	store_result: bool = true
) -> bool:

	if game == null or evocation == null:
		return false

	if not ForgottenEvocations.can_remove(game, evocation, context):
		return false
	var owner_id = evocation.assigned_mage if evocation.assigned_mage >= 0 else int(evocation.owner_id)
	if not _valid_player(game, owner_id):
		return false

	var owner = game.players[owner_id]
	var index = owner.evocations.find(evocation)
	if index == -1:
		return false

	var room_id = str(evocation.room_id)

	# Trigger before removal, as required by Stone Phoenix.
	game.emit_evocation_defeated_or_removed(
		evocation,
		"removed"
	)

	if not game.finalize_evocation_removal(evocation):
		return false

	if store_result:
		context["removed_evocation"] = evocation
		context["removed_evocation_room_id"] = room_id
		context["removed_evocation_success"] = true

	return true


func _heal_evocation(
	game,
	evocation,
	amount: int
) -> int:

	if game == null or evocation == null or amount <= 0:
		return 0

	var healed = min(amount, evocation.damage_cubes.size())

	for i in range(healed):
		var owner_id = int(evocation.damage_cubes.pop_back())
		game.return_owner_cubes(owner_id, 1)

	return healed


func convert_damage_cubes(
	damage_cubes: Array,
	new_owner_id: int,
	amount: int,
	selected_owners: Array = [],
	game = null
) -> int:

	var converted = 0
	var remaining := selected_owners.duplicate()

	for i in range(damage_cubes.size()):
		if converted >= amount:
			break

		if int(damage_cubes[i]) == new_owner_id:
			continue

		if not selected_owners.is_empty():
			var selected_index: int = -1
			for j in range(remaining.size()):
				var selected = remaining[j]
				if selected is Dictionary:
					if int(selected.get("cube_index", -1)) == i and int(selected.get("owner_id", -999)) == int(damage_cubes[i]):
						selected_index = j
						break
				elif int(selected) == int(damage_cubes[i]):
					selected_index = j
					break
			if selected_index < 0:
				continue
			remaining.remove_at(selected_index)
		if game != null:
			if game.take_owner_cubes(new_owner_id, 1) <= 0:
				break
			game.return_owner_cubes(int(damage_cubes[i]), 1)
		damage_cubes[i] = new_owner_id
		converted += 1

	return converted


# =============================================================================
# CORE EFFECT HANDLERS
# =============================================================================

func _resolve_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	if game == null:
		return false

	var caster_id = _caster(context)
	var amount = int(effect.get("amount", 0))
	if amount <= 0:
		return true

	if not context.has("models_damaged_by_effect"):
		context["models_damaged_by_effect"] = []

	var suppressed = _suppressed_triggers(effect)

	# Normally the target type comes from the Spell context.
	# A specific effect can override it.
	#
	# Example:
	# {
	#     "type": "damage",
	#     "amount": 2,
	#     "target": "room"
	# }
	var target_type = str(
		effect.get(
			"target",
			_target_type(context)
		)
	)

	if _is_dummy_target(context) \
	and target_type in ["model", "mage", "evocation"]:
		return true

	if target_type == "room":
		var room_id = _target_room(context)
		if room_id == "":
			print("resolve_damage: target Room missing")
			return false

		# Damage every Mage in the target Room.
		for player_index in range(game.players.size()):
			var mage = game.players[player_index].mage
			if mage.room_id != room_id:
				continue

			var dealt = _damage_mage(
				game,
				caster_id,
				player_index,
				amount,
				"spell",
				suppressed
			)

			if dealt > 0:
				register_damaged_model(
					context,
					{
						"type": "mage",
						"player_index": player_index,
						"room_id": room_id
					}
				)

		# Damage every Evocation in the target Room.
		for player in game.players:
			var snapshot = player.evocations.duplicate()

			for evocation in snapshot:
				if evocation == null:
					continue

				if evocation.room_id != room_id:
					continue

				var dealt = _damage_evocation(
					game,
					caster_id,
					evocation,
					amount,
					suppressed
				)

				if dealt > 0:
					register_damaged_model(
						context,
						{
							"type": "evocation",
							"evocation": evocation,
							"room_id": room_id
						}
					)

		return true

	if target_type == "evocation":
		var evocation = context.get("target_evocation")
		if evocation == null:
			print("resolve_damage: target Evocation missing")
			return false

		var dealt = _damage_evocation(
			game,
			caster_id,
			evocation,
			amount,
			suppressed
		)

		_record_evocation_damage(
			context,
			evocation,
			dealt
		)

		return true

	if target_type == "model":
		var model_type = str(
			context.get(
				"target_model_type",
				""
			)
		)

		if model_type == "" and context.has("target_player_index"):
			model_type = "mage"

		if model_type == "mage":
			var player_index = int(
				context.get(
					"target_player_index",
					-1
				)
			)

			if not _valid_player(
				game,
				player_index
			):
				return false

			var dealt = _damage_mage(
				game,
				caster_id,
				player_index,
				amount,
				"spell",
				suppressed
			)

			_record_mage_damage(
				context,
				game,
				player_index,
				dealt
			)

			return true

		if model_type == "evocation":
			var evocation = context.get(
				"target_evocation"
			)

			if evocation == null:
				print(
					"resolve_damage: target Model Evocation missing"
				)
				return false

			var dealt = _damage_evocation(
				game,
				caster_id,
				evocation,
				amount,
				suppressed
			)

			_record_evocation_damage(
				context,
				evocation,
				dealt
			)

			return true

		print(
			"resolve_damage: unknown Model type: ",
			model_type
		)

		return false

	if target_type == "mage":
		var player_index = int(
			context.get(
				"target_player_index",
				-1
			)
		)

		if not _valid_player(
			game,
			player_index
		):
			return false

		var dealt = _damage_mage(
			game,
			caster_id,
			player_index,
			amount,
			"spell",
			suppressed
		)

		_record_mage_damage(
			context,
			game,
			player_index,
			dealt
		)

		return true

	print(
		"resolve_damage: unsupported target type: ",
		target_type
	)

	return false


func _resolve_heal(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	if _is_dummy_target(context):
		return true

	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null:
		return false

	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true

	var selected_owners: Array = _choice_as_array(
		context.get(
			"selected_damage_owner_ids",
			null
		)
	)

	if context.has("selected_damage_owner_ids") and selected_owners.is_empty():
		return true

	var target_model_type: String = str(
		context.get(
			"target_model_type",
			""
		)
	)

	if target_model_type == "" \
	and int(
		context.get(
			"target_player_index",
			-1
		)
	) >= 0:
		target_model_type = "mage"

	var healed: int = 0

	if target_model_type == "evocation":
		var evocation = context.get(
			"target_evocation"
		)

		if evocation == null:
			return false

		var requested_owners: Array = selected_owners.duplicate()

		while healed < amount \
		and not evocation.damage_cubes.is_empty():
			if context.has("selected_damage_owner_ids") and requested_owners.is_empty():
				break
			var cube_owner: int = int(
				evocation.damage_cubes[0]
			)

			if not requested_owners.is_empty():
				cube_owner = int(
					requested_owners.pop_front()
				)

			var cube_index: int = evocation.damage_cubes.find(
				cube_owner
			)

			if cube_index == -1:
				if selected_owners.is_empty():
					cube_index = 0
					cube_owner = int(
						evocation.damage_cubes[0]
					)
				else:
					continue

			evocation.damage_cubes.remove_at(
				cube_index
			)
			game.return_owner_cubes(
				cube_owner,
				1
			)
			healed += 1

		context["effect_target_model_type"] = "evocation"

	else:
		var target: int = int(
			context.get(
				"target_player_index",
				caster_id
			)
		)

		if not _valid_player(
			game,
			target
		):
			return false

		var requested_owners: Array = selected_owners.duplicate()

		while healed < amount \
		and not game.players[
			target
		].mage.damage_cubes.is_empty():
			if context.has("selected_damage_owner_ids") and requested_owners.is_empty():
				break
			var cube_owner: int = int(
				game.players[
					target
				].mage.damage_cubes[0]
			)

			if not requested_owners.is_empty():
				cube_owner = int(
					requested_owners.pop_front()
				)

			var removed: int = game.heal_damage(
				target,
				cube_owner,
				1
			)

			if removed <= 0:
				if selected_owners.is_empty():
					break
				continue

			healed += removed

		context["effect_target_model_type"] = "mage"

	context["effect_damage_healed"] = healed

	return true

func _resolve_power(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	if game == null:
		return false

	var amount = int(effect.get("amount", 0))

	if mode == "gain_power":
		var caster_id = _caster(context)
		if caster_id == -1:
			game.add_black_rose_power(amount)
		else:
			game.add_player_power(caster_id, amount)
		return true

	if _is_dummy_target(context):
		return true

	var target = int(context.get("target_player_index", -1))
	if target < 0:
		return false
	if DeathEffectResolver.ignores(context, target):
		return true

	game.add_player_power(target, -amount)
	return true


func _resolve_place_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	if game == null:
		return false

	var room_id := ""

	# A Quest/Spell Effect printed as Room range 0 always means the caster's
	# current Room, even if another Effect in the same card uses a different
	# selected target Room.
	if str(effect.get("target", "")) == "room" \
	and str(effect.get("range", "")) == "0":
		room_id = str(context.get("caster_room_id", ""))
	else:
		room_id = _target_room(context)

	if room_id == "":
		print("place_instability: target Room missing")
		return false

	var caster_id = _caster(context)
	var amount = int(effect.get("amount", 1))

	var before_count: int = 0
	var target_room = game.get_room_by_id(
		room_id
	)

	if target_room != null:
		before_count = target_room.get_instability_count()

	if caster_id == -1:
		game.place_black_rose_instability(room_id, amount)
	else:
		game.place_player_instability(caster_id, room_id, amount)

	var after_count: int = before_count

	if target_room != null:
		after_count = target_room.get_instability_count()

	context["effect_target_room_id"] = room_id
	var actually_placed: int = max(
		0,
		after_count - before_count
	)
	context["effect_instability_placed"] = actually_placed

	# Cards such as Gaea's Lifeline need the number to survive into a later
	# Geoform sentence. Per-effect metadata is reset between sentences, so an
	# explicit store_as key is persistent within the Spell context.
	var store_key: String = str(effect.get("store_as", ""))
	if store_key != "":
		context[store_key] = actually_placed

	return true



# INSTABLE_CREEK_V1
func _resolve_remove_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	if game == null:
		return false

	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var room_id: String = _target_room(context)
	if room_id == "":
		print("remove_instability: target Room missing")
		return false

	var room = game.get_room_by_id(room_id)
	if room == null:
		print("remove_instability: Room not found: ", room_id)
		return false

	var amount: int = maxi(0, int(effect.get("amount", 0)))
	var up_to: bool = bool(effect.get("up_to", false))
	var store_key: String = str(
		effect.get("store_as", "instability_removed")
	)
	var choice_key: String = str(
		effect.get(
			"choice_key",
			"_selected_remove_instability_cubes"
		)
	)

	if amount <= 0:
		context[store_key] = 0
		context["effect_instability_removed"] = 0
		return true

	# First pass: choose the physical Instability cubes on the Lodge.
	# "up to" intentionally allows choosing zero cubes.
	if not context.has(choice_key):
		var options: Array = []
		var owner_occurrences: Dictionary = {}

		for cube_index in range(room.instability_cubes.size()):
			var owner_id: int = int(room.instability_cubes[cube_index])
			var ordinal: int = int(
				owner_occurrences.get(owner_id, 0)
			)
			owner_occurrences[owner_id] = ordinal + 1
			if effect.get("owner") == "self" and owner_id != caster_id:
				continue

			var owner_name: String = "Black Rose"
			if owner_id >= 0 and owner_id < game.players.size():
				owner_name = game.players[owner_id].player_name

			options.append({
				"token":
					"instability:"
					+ str(owner_id)
					+ ":"
					+ str(ordinal),
				"value": owner_id,
				"owner_id": owner_id,
				"owner_name": owner_name,
				"cube_room_id": room_id
			})

		var max_select: int = mini(amount, options.size())
		if max_select <= 0:
			context[store_key] = 0
			context["effect_instability_removed"] = 0
			return true

		var min_select: int = 0 if up_to else max_select
		var prompt: String = (
			"Choose up to " + str(max_select)
			+ " Instability cubes to remove."
			if up_to
			else "Choose " + str(max_select)
			+ " Instability cubes to remove."
		)

		if not game.request_effect_choice(
			caster_id,
			"instability_cubes",
			context,
			choice_key,
			options,
			min_select,
			max_select,
			prompt
		):
			return false

		return false

	var selected: Array = _choice_as_array(
		context.get(choice_key, [])
	)
	var remove_limit: int = mini(amount, selected.size())
	var removed: int = 0

	for selected_index in range(remove_limit):
		var selected_value = selected[selected_index]
		var owner_id: int = (
			int(selected_value.get("owner_id", 999999))
			if selected_value is Dictionary
			else int(selected_value)
		)

		if owner_id == 999999:
			continue

		if not room.remove_instability_cube(owner_id):
			continue

		game.return_owner_cubes(owner_id, 1)
		removed += 1

	context.erase(choice_key)
	context[store_key] = removed
	context["effect_instability_removed"] = removed
	context["effect_target_room_id"] = room_id

	print(
		"Player ", caster_id + 1,
		" removed ", removed,
		" Instability from ", room_id
	)

	return true


func _resolve_place_instability_from_context(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	if game == null:
		return false

	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var amount_key: String = str(
		effect.get("amount_key", "instability_removed")
	)
	var amount: int = maxi(
		0,
		int(context.get(amount_key, 0))
	)

	# Removing zero means there is nothing to place, so do not ask for a Room.
	if amount <= 0:
		context["effect_instability_placed"] = 0
		return true

	var origin_room_id: String = _target_room(context)
	if origin_room_id == "":
		print("place_instability_from_context: target Room missing")
		return false

	var distance: int = maxi(
		0,
		int(effect.get("range_from_target", 0))
	)
	var choice_key: String = str(
		effect.get(
			"choice_key",
			"_instability_from_context_destination_room_id"
		)
	)

	if not context.has(choice_key):
		var options: Array = []

		# This is printed Range from the original target, not movement, so
		# candidate Rooms obey the normal Effect range / line-of-sight rules.
		for room_value in game.room_id_by_coord.values():
			var destination_room_id: String = str(room_value)
			if not game.is_room_within_effect_range(
				origin_room_id,
				destination_room_id,
				distance
			):
				continue

			var destination_room = game.get_room_by_id(
				destination_room_id
			)
			var room_name: String = destination_room_id
			if destination_room != null:
				room_name = str(destination_room.room_name)

			options.append({
				"token":
					"room:instability_from_context:"
					+ destination_room_id,
				"value": destination_room_id,
				"room_id": destination_room_id,
				"target_type": "room",
				"name": room_name
			})

		if options.is_empty():
			return true

		# Do not overwrite target_room_id: a following Geoform must still check
		# the original target Room, not the Room chosen for this placement.
		if not game.request_effect_choice(
			caster_id,
			"secondary_room",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose a Room within "
			+ str(distance)
			+ " of the target."
		):
			return false

		return false

	var destination_room_id: String = str(
		context.get(choice_key, "")
	)
	context.erase(choice_key)

	if destination_room_id == "":
		return false

	# Revalidate after the choice (important for online/stale requests).
	if not game.is_room_within_effect_range(
		origin_room_id,
		destination_room_id,
		distance
	):
		print(
			"place_instability_from_context: invalid destination ",
			destination_room_id
		)
		return false

	var placed: int = game.place_instability(
		caster_id,
		destination_room_id,
		amount
	)

	context["effect_target_room_id"] = destination_room_id
	context["effect_instability_placed"] = placed
	context["last_instability_transfer_origin_room_id"] = origin_room_id
	context["last_instability_transfer_destination_room_id"] = (
		destination_room_id
	)
	context["last_instability_transfer_amount"] = placed

	return true


func _resolve_pain(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	var amount = int(effect.get("amount", 0))

	if not _valid_player(game, caster_id):
		return false

	if amount <= 0:
		return true

	game.deal_damage(-1, caster_id, amount)

	print(
		"Pain ",
		amount,
		": Black Rose -> Player ",
		caster_id + 1
	)
	return true


func _resolve_convert_damage(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var amount = int(effect.get("amount", 0))
	if amount <= 0:
		return true

	if mode != "convert_damage_on_caster" \
	and _is_dummy_target(context):
		return true

	if mode == "convert_damage_on_caster":
		var new_owner = int(effect.get("converter_owner_id", -1))
		var converted = convert_damage_cubes(
			game.players[caster_id].mage.damage_cubes,
			new_owner,
			amount, _choice_as_array(context.get("convert_mage:%d" % caster_id, null)), game
		)

		if caster_id < game.player_boards.size():
			game.player_boards[caster_id].refresh()

		context["effect_damage_converted"] = converted
		context["effect_target_model_type"] = "mage"

		print(
			"Converted ", converted,
			" Damage on Player ", caster_id + 1,
			" to owner ", new_owner
		)
		return true

	var target_type = _target_type(context)

	if target_type == "mage":
		var player_index = int(context.get("target_player_index", -1))
		if not _valid_player(game, player_index):
			return false

		if player_index == caster_id or DeathEffectResolver.ignores(context, player_index):
			return true

		var converted = convert_damage_cubes(
			game.players[player_index].mage.damage_cubes,
			caster_id,
			amount, _choice_as_array(context.get("convert_mage:%d" % player_index, null)), game
		)

		if player_index < game.player_boards.size():
			game.player_boards[player_index].refresh()

		context["effect_damage_converted"] = converted
		context["effect_target_model_type"] = "mage"

		print(
			"Convert damage: P", caster_id + 1,
			" converted ", converted,
			" Damage on P", player_index + 1
		)
		return true

	if target_type == "evocation":
		var evocation = context.get("target_evocation")
		if evocation == null:
			return false

		var controller_id: int = int(evocation.controller_id)
		if controller_id < 0:
			controller_id = int(evocation.owner_id)

		if controller_id == caster_id:
			return true

		var converted = convert_damage_cubes(
			evocation.damage_cubes,
			caster_id,
			amount, _choice_as_array(context.get("convert_evocation:%d" % evocation.get_instance_id(), null)), game
		)
		context["effect_damage_converted"] = converted
		context["effect_target_model_type"] = "evocation"

		print(
			"Convert damage: P", caster_id + 1,
			" converted ", converted,
			" Damage on ", evocation.evocation_name
		)
		return true

	if target_type == "room":
		var room_id = str(context.get("target_room_id", ""))
		if room_id == "":
			return false

		var total_converted: int = 0
		var room_key: String = "convert_room:" + room_id
		var selected: Array = _choice_as_array(context.get(room_key, null))

		# Normal runtime path: Game collected every eligible cube in the Room in
		# one choice, so the printed amount is a global cap across all Models.
		for selection_value in selected:
			if total_converted >= amount or not selection_value is Dictionary:
				break
			var selection: Dictionary = selection_value
			var model_type: String = str(selection.get("model_type", ""))
			var cube_index: int = int(selection.get("cube_index", -1))
			var old_owner: int = int(selection.get("owner_id", -999))
			var cubes: Array = []
			if model_type == "mage":
				var player_index: int = int(selection.get("player_index", -1))
				if not _valid_player(game, player_index):
					continue
				var mage = game.players[player_index].mage
				if mage == null or mage.in_cell or mage.room_id != room_id or DeathEffectResolver.ignores(context, player_index):
					continue
				cubes = mage.damage_cubes
			elif model_type == "evocation":
				var owner_index: int = int(selection.get("owner_index", -1))
				var evocation_index: int = int(selection.get("evocation_index", -1))
				if not _valid_player(game, owner_index) or evocation_index < 0 or evocation_index >= game.players[owner_index].evocations.size():
					continue
				var evocation = game.players[owner_index].evocations[evocation_index]
				if evocation == null or evocation.is_defeated() or evocation.room_id != room_id or (str(context.get("resolver_kind", "spell")) == "spell" and not ForgottenEvocations.ability(game, evocation, "ignore_spell_effects").is_empty()):
					continue
				cubes = evocation.damage_cubes
			else:
				continue
			if cube_index < 0 or cube_index >= cubes.size() or int(cubes[cube_index]) != old_owner or old_owner == caster_id:
				continue
			if game.take_owner_cubes(caster_id, 1) <= 0:
				break
			game.return_owner_cubes(old_owner, 1)
			cubes[cube_index] = caster_id
			total_converted += 1

		# Backward-compatible direct-test path: if no interactive selection was
		# supplied, convert up to `amount` eligible cubes across the Room once.
		if selected.is_empty():
			for player_index in range(game.players.size()):
				if total_converted >= amount:
					break
				var mage = game.players[player_index].mage
				if mage == null or mage.in_cell or mage.room_id != room_id or DeathEffectResolver.ignores(context, player_index):
					continue
				total_converted += convert_damage_cubes(
					mage.damage_cubes,
					caster_id,
					amount - total_converted,
					[], game
				)
			for player in game.players:
				if total_converted >= amount:
					break
				for evocation in player.evocations:
					if total_converted >= amount:
						break
					if evocation == null or evocation.is_defeated() or evocation.room_id != room_id or (str(context.get("resolver_kind", "spell")) == "spell" and not ForgottenEvocations.ability(game, evocation, "ignore_spell_effects").is_empty()):
						continue
					total_converted += convert_damage_cubes(
						evocation.damage_cubes,
						caster_id,
						amount - total_converted,
						[], game
					)

		for player_index in range(game.players.size()):
			if player_index < game.player_boards.size():
				game.player_boards[player_index].refresh()

		context["effect_target_room_id"] = room_id
		context["effect_damage_converted"] = total_converted
		return true

	print("resolve_convert_damage: unsupported target type: ", target_type)
	return false



func _resolve_convert_damage_each_other_mage(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var primary_target: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)

	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)

	if amount <= 0:
		return true

	for player_index in range(
		game.players.size()
	):
		# "each other Mage" excludes the primary target. The caster also
		# ignores conversion caused by their own Effect.
		if player_index == primary_target \
		or player_index == caster_id \
		or DeathEffectResolver.ignores(context, player_index) \
		or game.is_mage_in_cell(player_index):
			continue

		var converted: int = convert_damage_cubes(
			game.players[
				player_index
			].mage.damage_cubes,
			caster_id,
			amount, _choice_as_array(context.get("convert_mage:%d" % player_index, null)), game
		)

		if player_index < game.player_boards.size():
			game.player_boards[
				player_index
			].refresh()

		print(
			"Killer Fog: converted ",
			converted,
			" Damage on Player ",
			player_index + 1
		)

	return true


func _resolve_damage_within_distance_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null:
		return false

	var room_id: String = _target_room(
		context
	)

	if room_id == "":
		return false

	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)
	var distance: int = int(
		effect.get(
			"distance",
			0
		)
	)

	if amount <= 0:
		return true

	# Reuse the existing Lodge-distance damage primitive. The helper also
	# records every damaged Model in the current Effect context.
	return _damage_within_distance(
		game,
		caster_id,
		room_id,
		distance,
		amount,
		context,
		_suppressed_triggers(effect)
	)


func _resolve_place_instability_per_damaged_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(
		game,
		caster_id
	):
		return false

	var room_id: String = _target_room(
		context
	)

	if room_id == "":
		return false

	var damaged_models: Array = context.get(
		"models_damaged_by_effect",
		[]
	)

	var amount_per_model: int = int(
		effect.get(
			"amount_per_model",
			1
		)
	)
	var cap: int = int(
		effect.get(
			"max",
			999
		)
	)

	var amount: int = min(
		damaged_models.size()
		* amount_per_model,
		cap
	)

	if amount <= 0:
		return true

	game.place_player_instability(
		caster_id,
		room_id,
		amount
	)

	return true

# =============================================================================
# QUEST / CARD-ZONE EFFECT HANDLERS
# =============================================================================

func _side_has_any_element(
	side: Dictionary,
	required_elements: Array[String]
) -> bool:
	if required_elements.is_empty():
		return true

	# Enhancement requirements describe a condition, not this Spell's Element.
	var element: String = str(side.get("element", ""))
	return element == "all" or element in required_elements


func _resolve_return_revealed_spell_to_hand(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id := _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var required_elements: Array[String] = []
	for value in effect.get("required_elements", []):
		required_elements.append(str(value))

	# Backward compatibility with the first Quest JSON prototype.
	var legacy_symbol := str(effect.get("required_symbol", ""))
	if required_elements.is_empty() and legacy_symbol != "":
		required_elements.append(legacy_symbol)

	var player = game.players[caster_id]
	var eligible: Array = []

	for revealed in player.revealed_spells:
		if revealed == null or revealed.spell == null:
			continue
		if _side_has_any_element(revealed.get_active_side(), required_elements):
			eligible.append(revealed)

	# If there is no legal card, the sentence cannot be applied and is skipped.
	if eligible.is_empty():
		return true

	var selected = context.get("selected_revealed_spell", null)

	if selected == null and context.has("selected_revealed_spell_index"):
		var selected_index := int(context.get("selected_revealed_spell_index", -1))
		if selected_index >= 0 and selected_index < player.revealed_spells.size():
			selected = player.revealed_spells[selected_index]

	if selected == null and context.has("selected_revealed_spell_id"):
		var selected_id := str(context.get("selected_revealed_spell_id", ""))
		for revealed in eligible:
			if revealed.spell.id == selected_id:
				selected = revealed
				break

	# Quest resolution must never silently choose for the player.
	if selected == null:
		if str(context.get("resolver_kind", "")) == "quest":
			print("return_revealed_spell_to_hand: player choice missing")
			return false
		selected = eligible[0]

	if not selected in eligible:
		print("return_revealed_spell_to_hand: illegal selected Spell")
		return false

	player.revealed_spells.erase(selected)
	player.add_spell_to_hand(selected.spell)
	game._clear_player_board_spell_by_spell(caster_id, selected.spell)

	print(
		"Player ", caster_id + 1,
		" returned revealed ", selected.spell.card_name,
		" to Hand"
	)
	return true


func _resolve_search_grimoire_to_hand(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id := _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var player = game.players[caster_id]
	var amount: int = maxi(0, int(effect.get("amount", 1)))

	for i in range(amount):
		if player.grimoire.is_empty():
			break

		var selected_spell = context.get("selected_grimoire_spell", null)
		var selected_id := str(context.get("selected_grimoire_spell_id", ""))
		var selected_index := -1

		if selected_spell != null:
			selected_index = player.grimoire.find(selected_spell)
		elif selected_id != "":
			for index in range(player.grimoire.size()):
				if player.grimoire[index].id == selected_id:
					selected_index = index
					break
		else:
			if str(context.get("resolver_kind", "")) == "quest":
				print("search_grimoire_to_hand: player choice missing")
				return false
			selected_index = 0

		if selected_index < 0 or selected_index >= player.grimoire.size():
			print("search_grimoire_to_hand: selected Spell not in Grimoire")
			return false

		var spell: SpellCardState = player.grimoire[selected_index]
		player.grimoire.remove_at(selected_index)
		player.add_spell_to_hand(spell)

		print(
			"Player ", caster_id + 1,
			" searched ", spell.card_name,
			" from Grimoire"
		)

	# The card explicitly instructs the Mage to shuffle the Grimoire afterwards.
	game.shuffle_player_grimoire(caster_id)
	return true


func _resolve_draw_library(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	# Quests use the same resumable, one-School-per-card draw as Spell effects.
	var draw_effect := effect.duplicate()
	draw_effect["school_choice_key"] = str(effect.get("school_choice_key", "selected_school_id"))
	return _resolve_draw_from_library(draw_effect, context)


func _resolve_take_crown(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id := _caster(context)
	if not _valid_player(game, caster_id):
		return false

	return game.take_crown(caster_id)


func _choice_as_array(value) -> Array:
	if value == null:
		return []

	if value is Array:
		var values: Array = value
		return values.duplicate()

	return [value]


func _heal_any_mage_damage(
	game,
	player_index: int,
	amount: int,
	preferred_owners: Array = [],
	allow_fallback: bool = true
) -> int:
	if not _valid_player(game, player_index) or amount <= 0:
		return 0

	var mage = game.players[player_index].mage
	var healed: int = 0
	var owner_queue: Array = preferred_owners.duplicate()

	while healed < amount and not mage.damage_cubes.is_empty():
		var owner_id: int

		if not owner_queue.is_empty():
			owner_id = int(owner_queue.pop_front())
			if not owner_id in mage.damage_cubes:
				continue
		else:
			if not allow_fallback:
				break
			owner_id = int(mage.damage_cubes[-1])

		if mage.remove_damage(owner_id, 1) <= 0:
			continue

		game.return_owner_cubes(owner_id, 1)
		healed += 1

	if player_index < game.player_boards.size():
		game.player_boards[player_index].refresh()

	return healed


func _resolve_draw_grimoire_or_heal(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id := _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var player = game.players[caster_id]

	# Guarding Wisdom: if there is no Damage at all on the Mage Sheet,
	# draw from the Grimoire; otherwise heal Damage.
	if player.mage.get_damage() == 0:
		var draw_amount: int = maxi(0, int(effect.get("draw", 0)))
		for i in range(draw_amount):
			game.draw_player_spell(caster_id)
		return true

	var heal_amount: int = maxi(0, int(effect.get("heal", 0)))
	var has_explicit_selection: bool = context.has(
		"selected_damage_owner_ids"
	)
	var preferred_owners: Array = _choice_as_array(
		context.get(
			"selected_damage_owner_ids",
			null
		)
	)
	var healed: int = _heal_any_mage_damage(
		game,
		caster_id,
		heal_amount,
		preferred_owners,
		not has_explicit_selection
	)

	print(
		"Guarding Wisdom: Player ", caster_id + 1,
		" healed ", healed, " Damage"
	)
	return true


func _resolve_convert_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id := _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var room_id := _target_room(context)
	if room_id == "":
		print("convert_instability: target Room missing")
		return false

	var room = game.get_room_by_id(room_id)
	if room == null:
		return false

	var amount: int = maxi(0, int(effect.get("amount", 0)))
	if amount <= 0:
		return true

	var explicit_selection: bool = context.has(
		"selected_instability_owner_ids"
	)
	var requested_owners: Array = _choice_as_array(
		context.get(
			"selected_instability_owner_ids",
			null
		)
	)
	var converted: int = 0

	while converted < amount:
		var old_owner: int = 999999
		var cube_index: int = -1

		if not requested_owners.is_empty():
			var selected = requested_owners.pop_front()
			if selected is Dictionary:
				old_owner = int(selected.get("owner_id", 999999))
				cube_index = int(selected.get("cube_index", -1))
			else:
				old_owner = int(selected)
			if old_owner == caster_id or not old_owner in room.instability_cubes:
				continue
		else:
			if explicit_selection:
				break

			for owner_value in room.instability_cubes:
				var candidate: int = int(owner_value)
				if candidate != caster_id:
					old_owner = candidate
					break

		# No opponent Instability remains: the rest of the Effect cannot apply.
		if old_owner == 999999:
			break

		# A conversion replaces the old Cube with one of the caster's Cubes.
		if game.take_owner_cubes(caster_id, 1) <= 0:
			break

		if not room.convert_instability_cube(old_owner, caster_id, cube_index):
			game.return_owner_cubes(caster_id, 1)
			continue

		game.return_owner_cubes(old_owner, 1)

		converted += 1

	context["effect_target_room_id"] = room_id
	context["effect_instability_converted"] = converted

	print(
		"Player ", caster_id + 1,
		" converted ", converted,
		" Instability in ", room_id
	)
	return true



func _resolve_draw_grimoire(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var amount: int = max(
		0,
		int(
			effect.get(
				"amount",
				1
			)
		)
	)

	for i in range(amount):
		game.draw_player_spell(
			caster_id
		)

	return true


func _resolve_draw_quest(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var amount: int = max(
		0,
		int(
			effect.get(
				"amount",
				1
			)
		)
	)

	for i in range(amount):
		game.quest_manager.draw_quest(
			game,
			caster_id
		)

	return true


func _resolve_draw_forgotten(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var amount: int = max(
		0,
		int(
			effect.get(
				"amount",
				1
			)
		)
	)

	for i in range(amount):
		game.draw_forgotten_spell(
			caster_id
		)

	return true


func _place_mage_direct(
	game,
	player_index: int,
	room_id: String
) -> bool:
	if game == null:
		return false

	return game.place_mage_in_room_direct(
		player_index,
		room_id
	)


func _resolve_swap_with_target_mage_optional(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if not bool(
		context.get(
			"quest_optional_yes",
			false
		)
	):
		return true

	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)

	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id):
		return false

	var target_room_id: String = game.players[
		target_id
	].mage.room_id
	var destination_room_id: String = str(
		context.get(
			"secondary_room_id",
			""
		)
	)

	if target_room_id == "" \
	or destination_room_id == "":
		return false

	if not _place_mage_direct(
		game,
		caster_id,
		target_room_id
	):
		return false

	return _place_mage_direct(
		game,
		target_id,
		destination_room_id
	)


func _resolve_draw_event_optional_gain_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if not bool(
		context.get(
			"quest_optional_yes",
			false
		)
	):
		return true

	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var drawn = game.draw_event(
		caster_id,
		{
			"game": game,
			"drawing_player_index": caster_id
		}
	)

	if drawn == null:
		return false

	game.add_player_power(
		caster_id,
		int(
			effect.get(
				"power",
				0
			)
		)
	)

	return true


func _resolve_gain_power_if_no_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	if game.players[
		caster_id
	].mage.get_damage() <= 0:
		game.add_player_power(
			caster_id,
			int(
				effect.get(
					"amount",
					0
				)
			)
		)

	return true


func _resolve_heal_all_damage(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var mage = game.players[
		caster_id
	].mage
	var healed: int = 0

	while not mage.damage_cubes.is_empty():
		var owner_id: int = int(
			mage.damage_cubes[0]
		)
		var removed: int = game.heal_damage(
			caster_id,
			owner_id,
			1
		)

		if removed <= 0:
			break

		healed += removed

	context["effect_target_model_type"] = "mage"
	context["effect_damage_healed"] = healed

	return true


func _resolve_draw_event_then_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if not bool(
		context.get(
			"quest_optional_yes",
			false
		)
	):
		return true

	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)

	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id):
		return false

	var drawn = game.draw_event(
		caster_id,
		{
			"game": game,
			"drawing_player_index": caster_id
		}
	)

	if drawn == null:
		return false

	game.deal_damage(
		caster_id,
		target_id,
		int(
			effect.get(
				"damage",
				0
			)
		),
		"quest"
	)

	return true


func _resolve_damage_all_models_lodge(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)

	if game == null:
		return false

	for player_index in range(
		game.players.size()
	):
		if game.is_mage_in_cell(
			player_index
		):
			continue

		_damage_mage(
			game,
			caster_id,
			player_index,
			amount
		)

	for player in game.players:
		var snapshot: Array = player.evocations.duplicate()

		for evocation in snapshot:
			if evocation == null \
			or evocation.is_defeated():
				continue

			_damage_evocation(
				game,
				caster_id,
				evocation,
				amount
			)

	return true


func _resolve_place_target_mage_then_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)
	var room_id: String = str(
		effect.get(
			"room_id",
			""
		)
	)

	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id) \
	or room_id == "":
		return false

	if not _place_mage_direct(
		game,
		target_id,
		room_id
	):
		return false

	game.deal_damage(
		caster_id,
		target_id,
		int(
			effect.get(
				"damage",
				0
			)
		),
		"quest"
	)

	return true


func _resolve_shuffle_memories_into_grimoire_then_draw(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	game.shuffle_memories_into_grimoire(
		caster_id
	)

	var amount: int = int(
		effect.get(
			"amount",
			0
		)
	)

	for i in range(amount):
		game.draw_player_spell(
			caster_id
		)

	return true


func _resolve_summon_non_forgotten_evocation_choice(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var evocation_id: String = str(
		context.get(
			"chosen_evocation_id",
			""
		)
	)

	if not _valid_player(game, caster_id) \
	or evocation_id == "":
		return false

	var room_id: String = game.players[
		caster_id
	].mage.room_id

	var summoned = _summon(
		game,
		caster_id,
		evocation_id,
		room_id,
		context
	)

	return summoned != null


func _resolve_damage_or_place_instability(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var branch: String = str(
		context.get(
			"quest_branch",
			""
		)
	)

	if branch == "damage":
		return _resolve_damage(
			{
				"type": "damage",
				"amount": int(
					effect.get(
						"damage",
						0
					)
				),
				"target": "room"
			},
			context
		)

	if branch == "instability":
		return _resolve_place_instability(
			{
				"type": "place_instability",
				"amount": int(
					effect.get(
						"instability",
						0
					)
				),
				"target": "room"
			},
			context
		)

	return false


func _resolve_complete_owned_quest_choice(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var quest: QuestState = context.get(
		"selected_active_quest",
		null
	)

	if not _valid_player(game, caster_id) \
	or quest == null:
		return false

	return game.quest_manager.complete_active_quest(
		game,
		caster_id,
		quest
	)


func _resolve_black_rose_or_mage_power_loss(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var branch: String = str(
		context.get(
			"quest_branch",
			""
		)
	)

	if game == null:
		return false

	if branch == "black_rose":
		game.add_black_rose_power(
			-int(
				effect.get(
					"black_rose",
					0
				)
			)
		)
		return true

	if branch == "mage":
		var target_id: int = int(
			context.get(
				"target_player_index",
				-1
			)
		)

		if not _valid_player(
			game,
			target_id
		):
			return false

		game.add_player_power(
			target_id,
			-int(
				effect.get(
					"mage",
					0
				)
			)
		)

		return true

	return false


func _resolve_refresh_physical_action_token(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var player = game.players[
		caster_id
	]

	player.available_physical_actions = min(
		player.MAX_PHYSICAL_ACTIONS,
		player.available_physical_actions
		+ int(
			effect.get(
				"amount",
				1
			)
		)
	)

	if caster_id < game.player_boards.size():
		game.player_boards[
			caster_id
		].refresh()

	return true


func _resolve_give_forgotten_to_target(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(
		context.get(
			"target_player_index",
			-1
		)
	)
	var spell: SpellCardState = context.get(
		"selected_forgotten_spell",
		null
	)

	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id) \
	or spell == null \
	or not spell.forgotten:
		return false

	var hand_index: int = game.players[
		caster_id
	].hand.find(
		spell
	)

	if hand_index == -1:
		return false

	game.players[
		caster_id
	].hand.remove_at(
		hand_index
	)

	game.players[
		target_id
	].hand.append(
		spell
	)

	return true


func _resolve_draw_three_forgotten_keep_one(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var selected: SpellCardState = context.get(
		"selected_forgotten_spell",
		null
	)

	if not _valid_player(game, caster_id) \
	or selected == null:
		return false

	var draw_amount: int = mini(
		int(
			effect.get(
				"draw",
				3
			)
		),
		game.forgotten_deck.size()
	)

	var candidates: Array[SpellCardState] = []

	for offset in range(draw_amount):
		var index: int = (
			game.forgotten_deck.size()
			- 1
			- offset
		)

		if index < 0:
			break

		candidates.append(
			game.forgotten_deck[
				index
			]
		)

	if not candidates.has(
		selected
	):
		return false

	for candidate in candidates:
		if str(candidate.light_side.get("type", "")) == "on_draw":
			for drawn in candidates:
				game.forgotten_deck.erase(drawn)
			game.resolve_drawn_forgotten(caster_id, candidate, candidates)
			return true

	for candidate in candidates:
		game.forgotten_deck.erase(
			candidate
		)

		if candidate == selected:
			game.players[
				caster_id
			].hand.append(
				candidate
			)
		else:
			game.remove_forgotten_from_game(
				candidate
			)

	return true


func _resolve_activate_evocation_or_summon_nigredo(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var evocation = context.get(
		"selected_evocation_to_activate"
	)

	if evocation != null:
		return _activate_evocation(
			evocation,
			caster_id,
			context
		)

	var room_id: String = str(
		context.get(
			"target_room_id",
			""
		)
	)

	if room_id == "":
		return false

	var summoned = _summon(
		game,
		caster_id,
		"nigredo",
		room_id,
		context
	)

	if summoned == null:
		return false

	return _activate_evocation(
		summoned,
		caster_id,
		context
	)


func _resolve_steal_power_from_up_to_mages(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if not _valid_player(game, caster_id):
		return false

	var selected: Array = _choice_as_array(
		context.get(
			"selected_mage_indices",
			[]
		)
	)
	var amount_each: int = int(
		effect.get(
			"amount_each",
			1
		)
	)

	var total_gained: int = 0

	for target_value in selected:
		var target_id: int = int(
			target_value
		)

		if not _valid_player(game, target_id) \
		or target_id == caster_id:
			continue

		var before: int = game.players[
			target_id
		].power

		game.add_player_power(
			target_id,
			-amount_each
		)

		var actual_loss: int = max(
			0,
			before - game.players[
				target_id
			].power
		)

		total_gained += actual_loss

	if total_gained > 0:
		game.add_player_power(
			caster_id,
			total_gained
		)

	return true




# =============================================================================
# GEOMANCY — FORTUNA / CAUDA / CARCER / CONJUNCTIO / LIFELINE
# =============================================================================

func _geomancy_choice_array(value) -> Array:
	if value == null:
		return []
	if value is Array:
		return value.duplicate()
	return [value]


func _resolve_discard_active_events(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var amount: int = maxi(0, int(effect.get("amount", 0)))
	var up_to: bool = bool(effect.get("up_to", true))
	var choice_key: String = str(
		effect.get("choice_key", "_geomancy_event_discard_indices")
	)
	var store_key: String = str(
		effect.get("store_as", "events_discarded")
	)

	if amount <= 0:
		context[store_key] = 0
		return true

	if not context.has(choice_key):
		var options: Array = []
		for slot_index in range(game.active_events.size()):
			var event = game.active_events[slot_index]
			if event == null:
				continue
			options.append({
				"token": "geomancy:event:" + str(slot_index),
				"value": slot_index,
				"slot_index": slot_index,
				"name": event.event_name
			})

		var max_select: int = mini(amount, options.size())
		if max_select <= 0:
			context[store_key] = 0
			return true

		var min_select: int = 0 if up_to else max_select
		if game.request_effect_choice(
			caster_id,
			"event_discard",
			context,
			choice_key,
			options,
			min_select,
			max_select,
			"Choose up to %d Events to discard." % amount
		):
			return false
		return false

	var selected: Array = _geomancy_choice_array(
		context.get(choice_key, [])
	)
	var unique_slots: Array[int] = []
	for selected_value in selected:
		var slot_index: int = int(selected_value)
		if slot_index < 0 or slot_index >= game.active_events.size():
			continue
		if unique_slots.has(slot_index):
			continue
		if game.active_events[slot_index] == null:
			continue
		unique_slots.append(slot_index)

	var discarded: int = 0
	for slot_index in unique_slots:
		var event = game.active_events[slot_index]
		if event == null:
			continue
		game.active_events[slot_index] = null
		# Fortuna Major explicitly prevents the Black Rose from gaining the
		# Event's normal discard Power.
		game.discard_event(event, false)
		discarded += 1

	context.erase(choice_key)
	context[store_key] = discarded
	if game.has_node("EventBoard"):
		game.get_node("EventBoard").refresh_event_slots()

	return true


func _resolve_gain_power_from_context(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var amount_key: String = str(effect.get("amount_key", ""))
	var multiplier: int = int(effect.get("multiplier", 1))
	var amount: int = maxi(
		0,
		int(context.get(amount_key, 0)) * multiplier
	)
	if effect.has("max"):
		amount = mini(amount, maxi(0, int(effect.get("max", amount))))

	if amount > 0:
		game.add_player_power(caster_id, amount)
	return true


func _resolve_conditional_payment(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var cost_value = effect.get("cost", {})
	if not cost_value is Dictionary:
		return false
	var cost: Dictionary = cost_value.duplicate(true)

	var state_key: String = str(
		effect.get("state_key", "_geomancy_conditional_payment_state")
	)
	var optional: bool = bool(effect.get("optional", false))
	var state: String = str(context.get(state_key, ""))

	if state == "skipped":
		context.erase(state_key)
		return true

	if state != "paid":
		if optional and state == "":
			var game = _game(context)
			var caster_id: int = _caster(context)
			if game == null or not _valid_player(game, caster_id):
				return false

			var decision_key: String = state_key + "_decision"
			if not context.has(decision_key):
				var options: Array = [
					{
						"token": "geomancy:payment:skip",
						"value": false,
						"name": "Do not pay"
					},
					{
						"token": "geomancy:payment:pay",
						"value": true,
						"name": "Pay the cost"
					}
				]
				if game.request_effect_choice(
					caster_id,
					"optional_payment",
					context,
					decision_key,
					options,
					1,
					1,
					"Pay the optional cost?"
				):
					return false
				return false

			var pay: bool = bool(context.get(decision_key, false))
			context.erase(decision_key)
			if not pay:
				context.erase(state_key)
				return true

			context[state_key] = "paying"

		cost["_conditional_payment_cost"] = true
		if not resolve_effect(cost, context):
			return false

		var paid_key: String = str(
			cost.get("paid_store_as", "_geomancy_payment_paid")
		)
		if not bool(context.get(paid_key, true)):
			context.erase(paid_key)
			context.erase(state_key)
			return true

		context.erase(paid_key)
		context[state_key] = "paid"

	var nested = effect.get("effects", [])
	if not nested is Array:
		return false

	var success: bool = resolve_effects(nested, context)
	if success:
		context.erase(state_key)
	return success


func _resolve_discard_spell(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var amount: int = maxi(0, int(effect.get("amount", 1)))
	var choice_key: String = str(
		effect.get("choice_key", "_geomancy_discard_spell_ids")
	)
	var paid_key: String = str(
		effect.get("paid_store_as", "_geomancy_payment_paid")
	)

	if amount <= 0:
		context[paid_key] = true
		return true

	if not context.has(choice_key):
		var options: Array = []
		for hand_index in range(game.players[caster_id].hand.size()):
			var spell = game.players[caster_id].hand[hand_index]
			options.append({
				"token": "geomancy:hand:" + str(hand_index),
				"value": spell.id,
				"spell_id": spell.id,
				"name": spell.card_name
			})

		if options.size() < amount:
			context[paid_key] = false
			return true

		if game.request_effect_choice(
			caster_id,
			"spell_discard",
			context,
			choice_key,
			options,
			amount,
			amount,
			"Choose %d Spell%s from your Hand to discard." % [
				amount,
				"" if amount == 1 else "s"
			]
		):
			return false
		return false

	var selected_ids: Array = _geomancy_choice_array(
		context.get(choice_key, [])
	)
	if selected_ids.size() != amount:
		context.erase(choice_key)
		context[paid_key] = false
		return true

	var success: bool = game.discard_player_spells_by_id(
		caster_id,
		selected_ids
	)
	context.erase(choice_key)
	context[paid_key] = success
	return true


func _geomancy_unsolved_quest_options(
	game,
	player_id: int
) -> Array:
	var options: Array = []
	if not _valid_player(game, player_id):
		return options

	for quest in game.players[player_id].active_quests:
		if quest == null or quest.is_solved():
			continue
		options.append({
			"token": "geomancy:unsolved:active:" + str(quest.get_instance_id()),
			"value": {
				"zone": "active",
				"quest": quest
			},
			"name": quest.get_name()
		})

	for quest in game.players[player_id].completed_quests:
		if quest == null or quest.is_solved():
			continue
		options.append({
			"token": "geomancy:unsolved:completed:" + str(quest.get_instance_id()),
			"value": {
				"zone": "completed",
				"quest": quest
			},
			"name": quest.get_name()
		})

	return options


func _geomancy_return_quest_progress_cubes(
	game,
	player_id: int,
	quest
) -> void:
	if game == null or quest == null:
		return
	var progress: int = maxi(0, int(quest.progress))
	if progress > 0:
		game.return_owner_cubes(player_id, progress)


func _resolve_discard_unsolved_quest(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var choice_key: String = str(
		effect.get("choice_key", "_geomancy_unsolved_quest")
	)
	var paid_key: String = str(
		effect.get("paid_store_as", "_geomancy_payment_paid")
	)

	if not context.has(choice_key):
		var options: Array = _geomancy_unsolved_quest_options(
			game,
			caster_id
		)
		if options.is_empty():
			context[paid_key] = false
			return true

		if game.request_effect_choice(
			caster_id,
			"unsolved_quest",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose one of your Unsolved Quests to discard."
		):
			return false
		return false

	var selected = context.get(choice_key, null)
	context.erase(choice_key)
	if not selected is Dictionary:
		context[paid_key] = false
		return true

	var quest = selected.get("quest", null)
	var zone: String = str(selected.get("zone", ""))
	if quest == null:
		context[paid_key] = false
		return true

	var player = game.players[caster_id]
	var removed: bool = false
	if zone == "active" and quest in player.active_quests:
		player.active_quests.erase(quest)
		removed = true
	elif zone == "completed" and quest in player.completed_quests:
		player.completed_quests.erase(quest)
		removed = true

	if removed:
		_geomancy_return_quest_progress_cubes(
			game,
			caster_id,
			quest
		)
		game.refresh_player_board(caster_id)

	context[paid_key] = removed
	return true


func _resolve_discard_solved_quest(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var target_id: int = int(
		context.get(
			"target_player_index",
			context.get("marked_player_index", -1)
		)
	)
	if not _valid_player(game, target_id):
		return false

	var choice_key: String = str(
		effect.get("choice_key", "_geomancy_solved_quest")
	)

	if not context.has(choice_key):
		var options: Array = []
		for quest in game.players[target_id].completed_quests:
			if quest == null or not quest.is_solved():
				continue
			options.append({
				"token": "geomancy:solved:" + str(quest.get_instance_id()),
				"value": quest,
				"name": quest.get_name()
			})

		# If the target has no Solved Quest, this sentence simply does nothing.
		if options.is_empty():
			return true

		if game.request_effect_choice(
			target_id,
			"solved_quest",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose a Solved Quest to discard."
		):
			return false
		return false

	var quest = context.get(choice_key, null)
	context.erase(choice_key)
	if quest == null:
		return true

	if quest in game.players[target_id].completed_quests:
		game.players[target_id].completed_quests.erase(quest)
		# Solved Quest progress cubes have already been returned by the normal
		# Quest solve flow; discarding the card must not return them twice.
		game.refresh_player_board(target_id)

	return true


func _resolve_draw_from_memories(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	for _i in range(maxi(0, int(effect.get("amount", 1)))):
		game.draw_random_memory(caster_id)
	return true


func _resolve_draw_from_library(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var school_key: String = str(
		effect.get("school_choice_key", "_geomancy_library_school")
	)
	var progress_key := school_key + "_drawn"
	var amount := maxi(0, int(effect.get("amount", 1)))
	var drawn := int(context.get(progress_key, 0))
	if drawn >= amount:
		context.erase(progress_key)
		return true

	# Each Library draw has its own School choice. Retain the number already
	# drawn while this same Effect pauses for the next decision.
	if context.has(school_key):
		var school_id := str(context[school_key])
		context.erase(school_key)
		if not game.is_school_active(school_id):
			return false
		var card: SpellCardState = game.draw_from_school_library(school_id)
		if card != null:
			game.players[caster_id].add_spell_to_hand(card)
		drawn += 1
		context[progress_key] = drawn
		if drawn >= amount:
			context.erase(progress_key)
			return true

	if not context.has(school_key):
		var options: Array = []
		for school_value in game.active_school_ids:
			var school_id: String = str(school_value)
			var library: Array = game.school_libraries.get(school_id, [])
			var discard: Array = game.school_discards.get(school_id, [])
			if library.is_empty() and discard.is_empty():
				continue
			options.append({
				"token": "geomancy:school:" + school_id,
				"value": school_id,
				"school_id": school_id,
				"name": school_id
			})

		if options.is_empty():
			context.erase(progress_key)
			return true

		if game.request_effect_choice(
			caster_id,
			"library_school",
			context,
			school_key,
			options,
			1,
			1,
			"Choose the School Library for card %d / %d." % [drawn + 1, amount]
		):
			return false
		return false

	return false


func _resolve_place_self_in_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var room_id: String = str(
		effect.get(
			"room_id",
			context.get("target_room_id", "")
		)
	)
	if room_id == "":
		return false

	return game.place_mage_in_room_direct(
		caster_id,
		room_id
	)


func _resolve_place_self_in_target_room(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(context.get("target_player_index", -1))
	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id):
		return false

	var room_id: String = str(game.players[target_id].mage.room_id)
	if room_id == "":
		return false

	return game.place_mage_in_room_direct(
		caster_id,
		room_id
	)


func _resolve_activate_evocation_owned_by_target_under_control(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	var target_id: int = int(context.get("target_player_index", -1))
	if not _valid_player(game, caster_id) \
	or not _valid_player(game, target_id):
		return false

	var choice_key: String = str(
		effect.get(
			"choice_key",
			"_geomancy_target_evocation_to_activate"
		)
	)

	if not context.has(choice_key):
		var target_room_id: String = str(
			game.players[target_id].mage.room_id
		)
		var range_value = effect.get("range_from_target", 2)
		var options: Array = []

		for evocation_index in range(
			game.players[target_id].evocations.size()
		):
			var evocation = game.players[target_id].evocations[
				evocation_index
			]
			if evocation == null or evocation.is_defeated():
				continue
			if not game.is_room_within_effect_range(
				target_room_id,
				str(evocation.room_id),
				range_value
			):
				continue

			options.append({
				"token":
					"geomancy:target_evocation:"
					+ str(target_id)
					+ ":"
					+ str(evocation_index),
				"value": evocation,
				"owner_id": target_id,
				"evocation_index": evocation_index,
				"name": evocation.get_display_name()
			})

		if options.is_empty():
			return true

		if game.request_effect_choice(
			caster_id,
			"target_evocation",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose one of the target Mage's Evocations to activate."
		):
			return false
		return false

	var evocation = context.get(choice_key, null)
	context.erase(choice_key)
	if evocation == null:
		return true

	var activation_context: Dictionary = context.duplicate(true)
	activation_context["controller_id"] = caster_id
	return game.activate_evocation(
		evocation,
		caster_id,
		activation_context
	)


func _resolve_heal_from_context(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var amount_key: String = str(
		effect.get("amount_key", "instability_removed")
	)
	var amount: int = maxi(
		0,
		int(context.get(amount_key, 0))
		* int(effect.get("multiplier", 1))
	)

	var mage = game.players[caster_id].mage
	var heal_count: int = mini(
		amount,
		mage.damage_cubes.size()
	)
	if heal_count <= 0:
		return true

	var choice_key: String = str(
		effect.get(
			"choice_key",
			"_geomancy_heal_damage_owner_ids"
		)
	)

	if not context.has(choice_key):
		var options: Array = []
		var owner_occurrences: Dictionary = {}

		for owner_value in mage.damage_cubes:
			var owner_id: int = int(owner_value)
			var ordinal: int = int(
				owner_occurrences.get(owner_id, 0)
			)
			owner_occurrences[owner_id] = ordinal + 1
			var owner_name: String = "Black Rose"
			if owner_id >= 0 and owner_id < game.players.size():
				owner_name = game.players[owner_id].player_name

			options.append({
				"token":
					"geomancy:heal:"
					+ str(owner_id)
					+ ":"
					+ str(ordinal),
				"value": owner_id,
				"owner_id": owner_id,
				"owner_name": owner_name
			})

		if game.request_effect_choice(
			caster_id,
			"heal_damage",
			context,
			choice_key,
			options,
			heal_count,
			heal_count,
			"Choose %d Damage to heal." % heal_count
		):
			return false
		return false

	var owner_ids: Array = _geomancy_choice_array(
		context.get(choice_key, [])
	)
	var healed: int = _heal_any_mage_damage(
		game,
		caster_id,
		heal_count,
		owner_ids,
		false
	)
	context.erase(choice_key)
	context["effect_damage_healed"] = healed
	return true


# =============================================================================
# GROUPED SCALED EFFECTS
# =============================================================================

func _resolve_scaled_effect(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if game == null:
		return false

	match mode:
		"damage_per_self_damage":
			if _is_dummy_target(context):
				return true

			if not _valid_player(game, caster_id):
				return false

			var source = game.players[caster_id].mage.get_damage()
			var amount = _scaled_amount(
				source,
				effect,
				"damage_per_step"
			)

			if amount < 0:
				return false

			if amount <= 0:
				return true

			var damage_effect: Dictionary = {
				"type": "damage",
				"amount": amount,
				"target": str(
					effect.get(
						"target",
						_target_type(context)
					)
				)
			}

			return _resolve_damage(
				damage_effect,
				context
			)

		"damage_per_black_rose_damage":
			if _is_dummy_target(context):
				return true

			if not _valid_player(game, caster_id):
				return false

			var source = game.players[caster_id].mage.get_damage_from(-1)
			var amount = _scaled_amount(
				source,
				effect,
				"damage_per_step"
			)

			if amount < 0:
				return false

			if amount <= 0:
				return true

			return _resolve_damage(
				{
					"type": "damage",
					"amount": amount,
					"target": _target_type(context)
				},
				context
			)

		"damage_secondary_mage_per_self_damage":
			var primary = int(context.get("target_player_index", -1))
			var target = int(
				context.get("secondary_target_player_index", -1)
			)

			if not _valid_player(game, caster_id) \
			or not _valid_player(game, target):
				print("Peak of Agony: secondary target missing")
				return false

			if target == primary:
				print(
					"Peak of Agony: secondary target must be different from primary target"
				)
				return false

			var source = game.players[caster_id].mage.get_damage()
			var amount = _scaled_amount(
				source,
				effect,
				"damage_per_step"
			)
			if amount < 0:
				return false
			if amount > 0:
				_damage_mage(
					game,
					caster_id,
					target,
					amount
				)

			print(
				"Peak of Agony secondary damage: ", source,
				" self Damage -> ", max(amount, 0),
				" Damage to Player ", target + 1
			)
			return true

		"gain_power_per_black_rose_damage":
			if not _valid_player(game, caster_id):
				return false

			var source = game.players[caster_id].mage.get_damage_from(-1)
			var amount = _scaled_amount(
				source,
				effect,
				"power_per_step"
			)
			if amount < 0:
				return false
			if amount > 0:
				game.add_player_power(caster_id, amount)

			print(
				"Master of Pleasure: ", source,
				" Black Rose Damage -> ", max(amount, 0),
				" Power"
			)
			return true

		"place_instability_at_defeated_mage_room_per_self_damage":
			var event = context.get("trigger_event")
			if event == null or not _valid_player(game, caster_id):
				return false

			var room_id = str(event.target_room_id)
			if room_id == "":
				print("Liquefy the Pain: defeated Mage has no Room")
				return false

			var source = game.players[caster_id].mage.get_damage()
			var amount = _scaled_amount(
				source,
				effect,
				"instability_per_step",
				2,
				1,
				4
			)
			if amount < 0:
				return false
			if amount > 0:
				game.place_player_instability(caster_id, room_id, amount)
			return true

		"place_instability_per_black_rose_damage_on_effect_damaged_models":
			if not _valid_player(game, caster_id):
				return false

			var models: Array = context.get(
				"models_damaged_by_effect",
				[]
			)

			var source: int = 0

			for model_value in models:
				if not model_value is Dictionary:
					continue

				var model: Dictionary = model_value
				var model_type: String = str(model.get("type", ""))

				if model_type == "mage":
					var target: int = int(
						model.get("player_index", -1)
					)
					if _valid_player(game, target):
						source += game.players[target].mage.get_damage_from(-1)

				elif model_type == "evocation":
					var evocation = model.get("evocation", null)
					if evocation != null:
						source += evocation.get_damage_from(-1)

			var amount: int = min(
				source * int(effect.get("instability_per_damage", 1)),
				int(effect.get("max", 4))
			)

			if amount <= 0:
				return true

			var room_id: String = _target_room(context)
			if room_id == "":
				print("Submission: target Room missing")
				return false

			game.place_player_instability(
				caster_id,
				room_id,
				amount
			)

			return true

		"place_instability_per_self_black_rose_damage":
			if not _valid_player(game, caster_id):
				return false

			var room_id: String = _target_room(context)
			if room_id == "":
				print("Heart of Ice: target Room missing")
				return false

			var source = game.players[caster_id].mage.get_damage_from(-1)
			var amount = min(
				source * int(effect.get("instability_per_damage", 1)),
				int(effect.get("max", 4))
			)

			if amount > 0:
				game.place_player_instability(caster_id, room_id, amount)
			return true

		"damage_per_revealed_active_element":
			if _is_dummy_target(context):
				return true

			if not _valid_player(game, caster_id):
				return false

			var element = str(effect.get("element", ""))
			var count = _revealed_element_count(game, caster_id, element)
			if count < 0:
				return false

			var amount = count * int(effect.get("amount_per_element", 1))
			if amount <= 0:
				return true

			return _resolve_damage(
				{
					"type": "damage",
					"amount": amount,
					"target": _target_type(context)
				},
				context
			)

		"place_instability_per_revealed_active_element":
			if _is_dummy_target(context):
				return true

			if not _valid_player(game, caster_id):
				return false

			var element = str(effect.get("element", ""))
			var count = _revealed_element_count(game, caster_id, element)
			if count < 0:
				return false

			var amount = count * int(effect.get("amount_per_element", 1))
			if amount <= 0:
				return true

			var model_type = str(context.get("target_model_type", ""))
			if model_type == "" and context.has("target_player_index"):
				model_type = "mage"

			var room_id = ""
			if model_type == "mage":
				var target = int(context.get("target_player_index", -1))
				if not _valid_player(game, target):
					return false
				room_id = game.players[target].mage.room_id
			elif model_type == "evocation":
				var evocation = context.get("target_evocation")
				if evocation == null:
					return false
				room_id = evocation.room_id
			else:
				print(
					"Athanor Eruption: invalid target Model type: ",
					model_type
				)
				return false

			if room_id == "":
				print("Athanor Eruption: target Model has no Room")
				return false

			game.place_player_instability(caster_id, room_id, amount)
			return true

	return false


# =============================================================================
# GROUPED SUMMON / REMOVE / ACTIVATE
# =============================================================================

func _resolve_summon_effect(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var evocation_id = ""
	var room_id = ""

	match mode:
		"summon_evocation":
			evocation_id = str(effect.get("evocation_id", ""))
			var room_mode = str(effect.get("room", ""))

			if effect.has("room_id"):
				room_id = str(effect.get("room_id", ""))
				context["effect_target_room_id"] = room_id
			elif room_mode == "trigger_evocation_room":
				room_id = str(context.get("trigger_evocation_room_id", ""))
			elif room_mode == "caster_room":
				room_id = str(context.get("caster_room_id", ""))
			else:
				room_id = str(context.get("target_room_id", ""))
				# Triggered Room-target Traps such as Liquefy the Pain determine
				# their Room from the event that caused the trigger. The card text
				# targets the Room the defeated Model was in; no target is chosen
				# when the Trap is armed.
				if room_id == "":
					var trigger_event = context.get("trigger_event")
					if trigger_event != null:
						room_id = str(trigger_event.target_room_id)
						if room_id == "":
							room_id = str(trigger_event.source_room_id)
				if room_id != "":
					context["target_room_id"] = room_id
					context["effect_target_room_id"] = room_id

		"summon_evocation_at_triggering_model":
			evocation_id = str(effect.get("evocation_id", ""))
			room_id = str(context.get("triggering_room_id", ""))

		"summon_same_evocation_as_trigger":
			var trigger_evocation = context.get("trigger_evocation")
			if trigger_evocation == null:
				print("summon_same_evocation_as_trigger: trigger Evocation missing")
				return false
			evocation_id = str(trigger_evocation.evocation_id)
			room_id = str(context.get("trigger_evocation_room_id", ""))

		"summon_evocation_from_deck":
			if not bool(context.get("removed_evocation_success", false)):
				print("Soul Transfer: no Construct was removed")
				return false

			evocation_id = str(context.get("chosen_evocation_id", ""))
			if evocation_id == "":
				print("Soul Transfer: no Evocation chosen from deck")
				return false

			var data = game.evocation_database.get_evocation(evocation_id)
			if data.is_empty():
				print("Soul Transfer: unknown Evocation ", evocation_id)
				return false

			if game.get_available_evocation_copies(evocation_id) <= 0:
				print(
					"Soul Transfer: ", evocation_id,
					" is not available in the Evocation Deck"
				)
				return false

			var max_health = int(effect.get("max_health", 3))
			if int(data.get("health", 999)) > max_health:
				print(
					"Soul Transfer: ", data.get("name", evocation_id),
					" has Health ", data.get("health", 999),
					" > ", max_health
				)
				return false

			room_id = str(context.get("target_room_id", ""))

		"summon_evocation_at_removed_evocation":
			if not bool(context.get("removed_evocation_success", false)):
				print("Fountain of the Three: no Evocation was removed")
				return false

			evocation_id = str(effect.get("evocation_id", ""))
			room_id = str(context.get("removed_evocation_room_id", ""))

	if evocation_id == "" or room_id == "":
		print(mode, ": missing Evocation id or Room")
		return false

	var summoned = _summon(
		game,
		caster_id,
		evocation_id,
		room_id,
		context
	)

	if summoned == null:
		if bool(context.get("summon_declined", false)):
			return true
		print(mode, ": summon failed")
		return false

	print(
		mode, ": summoned ",
		summoned.evocation_name,
		" in ", room_id
	)
	return true



# A_BURNING_WORLD_V1
# =============================================================================
# A BURNING WORLD
# =============================================================================

func _resolve_summon_evocations_distinct_rooms(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var evocation_id: String = str(
		effect.get("evocation_id", "")
	)
	var requested_count: int = max(
		0,
		int(effect.get("count", 0))
	)

	if evocation_id == "" or requested_count <= 0:
		return true

	var available_count: int = min(
		requested_count,
		game.get_available_evocation_copies(
			evocation_id
		)
	)

	if available_count <= 0:
		return true

	var choice_key: String = str(
		effect.get(
			"room_choice_key",
			"distinct_summon_rooms"
		)
	)
	var result_key: String = str(
		effect.get(
			"summoned_context_key",
			"last_distinct_summoned_evocations"
		)
	)

	if not context.has(choice_key):
		var options: Array = []
		var seen_rooms: Dictionary = {}

		for room_value in game.room_id_by_coord.values():
			var room_id: String = str(room_value)

			if room_id == "" \
			or seen_rooms.has(room_id) \
			or not game.is_lodge_room_id(room_id):
				continue

			seen_rooms[room_id] = true

			var room = game.get_room_by_id(room_id)
			if effect.has("room_color") and (room == null or str(room.get_room_data().get("color", "")) != str(effect.room_color)):
				continue
			var room_name: String = (
				str(room.room_name)
				if room != null
				else room_id
			)

			options.append({
				"token": "room:" + room_id,
				"value": room_id,
				"target_type": "room",
				"room_id": room_id,
				"name": room_name
			})

		if options.size() < available_count:
			return false

		game.request_effect_choice(
			caster_id,
			"distinct_summon_rooms",
			context,
			choice_key,
			options,
			available_count,
			available_count,
			"Choose "
			+ str(available_count)
			+ " different Rooms for the Myrmidones."
		)

		return false

	var selected_value = context.get(choice_key)
	if not selected_value is Array:
		return false

	var selected_rooms: Array = selected_value
	if selected_rooms.size() != available_count:
		return false

	var unique_rooms: Dictionary = {}

	for room_value in selected_rooms:
		var room_id: String = str(room_value)

		if room_id == "" \
		or unique_rooms.has(room_id) \
		or not game.is_lodge_room_id(room_id):
			return false

		unique_rooms[room_id] = true

	context.erase(choice_key)
	context[result_key] = []

	game.queue_resolution({
		"type": "summon_distinct_evocations",
		"owner_id": caster_id,
		"evocation_id": evocation_id,
		"room_ids": selected_rooms.duplicate(),
		"cursor": 0,
		"context": context,
		"result_key": result_key
	})

	return true


func _resolve_activate_distinct_summoned_evocations(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var source_key: String = str(
		effect.get(
			"summoned_context_key",
			"last_distinct_summoned_evocations"
		)
	)
	var choice_key: String = str(
		effect.get(
			"choice_key",
			"distinct_summoned_evocations_to_activate"
		)
	)
	var evocation_id: String = str(
		effect.get("evocation_id", "")
	)

	var candidates: Array = []

	for candidate in context.get(source_key, []):
		if not candidate is EvocationState:
			continue

		var evocation: EvocationState = candidate

		if evocation.is_defeated() \
		or not game.is_evocation_in_play(evocation):
			continue

		if evocation_id != "" \
		and str(evocation.evocation_id) != evocation_id:
			continue

		if not candidates.has(evocation):
			candidates.append(evocation)

	var requested_count: int = max(
		0,
		int(effect.get("count", 0))
	)
	var actual_count: int = min(
		requested_count,
		candidates.size()
	)

	if actual_count <= 0:
		return true

	var selected: Array = []

	if candidates.size() <= actual_count:
		selected = candidates.duplicate()
	elif not context.has(choice_key):
		var options: Array = []

		for evocation in candidates:
			options.append({
				"token":
					"evocation:"
					+ str(evocation.owner_id)
					+ ":"
					+ str(
						game.players[
							evocation.owner_id
						].evocations.find(evocation)
					),
				"value": evocation,
				"target_type": "evocation",
				"name": evocation.get_display_name(),
				"room_id": evocation.room_id
			})

		game.request_effect_choice(
			caster_id,
			"distinct_summoned_evocations",
			context,
			choice_key,
			options,
			actual_count,
			actual_count,
			"Choose "
			+ str(actual_count)
			+ " different Myrmidones to activate."
		)

		return false
	else:
		var selected_value = context.get(choice_key)
		if not selected_value is Array:
			return false
		selected = selected_value

	if selected.size() != actual_count:
		return false

	var unique: Dictionary = {}

	for selected_value in selected:
		if not selected_value is EvocationState:
			return false

		var evocation: EvocationState = selected_value
		var instance_id: int = evocation.get_instance_id()

		if unique.has(instance_id) \
		or not candidates.has(evocation):
			return false

		unique[instance_id] = true

	context.erase(choice_key)

	for index in range(
		selected.size() - 1,
		-1,
		-1
	):
		var evocation: EvocationState = selected[index]

		game.activate_evocation(
			evocation,
			game.get_evocation_controller_id(evocation),
			{}
		)

	return true


func _resolve_remove_evocation_effect(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)

	if _is_dummy_target(context):
		return true

	var evocation = context.get("target_evocation")

	if mode == "remove_owned_evocation":
		evocation = context.get(
			"selected_evocation_to_remove",
			evocation
		)

	if game == null or evocation == null:
		return false

	var store_result = false

	if mode == "remove_owned_evocation":
		if not _valid_player(game, caster_id):
			return false

		if evocation.owner_id != caster_id:
			print("Soul Transfer: selected Evocation is not owned by caster")
			return false

		var archetype = str(effect.get("evocation_archetype", ""))
		if archetype != "" \
		and str(evocation.archetype) != archetype:
			print("Soul Transfer: selected Evocation has wrong archetype")
			return false

		store_result = true

	elif mode == "remove_evocation_with_max_health":
		if evocation.health > int(effect.get("max_health", 3)):
			print(
				"Fountain of the Three: ", evocation.evocation_name,
				" has Health ", evocation.health,
				" > ", effect.get("max_health", 3)
			)
			return false
		store_result = true

	var name = str(evocation.evocation_name)
	var room_id = str(evocation.room_id)

	if not _remove_evocation(game, evocation, context, store_result):
		print(mode, ": Evocation is not in play")
		return false

	print(mode, ": removed ", name, " from ", room_id)
	return true


func _resolve_activation_effect(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)

	if _is_dummy_target(context) \
	and mode in [
		"activate_target_evocation",
		"activate_target_evocation_under_control"
	]:
		return true

	var evocation = null
	var controller_id = caster_id
	var bonus = 0

	match mode:
		"activate_summoned_evocation":
			evocation = context.get("last_summoned_evocation")
			if evocation != null:
				controller_id = evocation.owner_id
			if effect.get("controller") == "crown": controller_id = game.crown_owner_id
			bonus = int(effect.get("strength_bonus", 0))

		"activate_owned_evocation":
			if not _valid_player(game, caster_id):
				return false

			var preferred = context.get("selected_evocation_to_activate")
			var allow_auto_select: bool = (
				str(context.get("resolver_kind", "")) != "quest"
			)
			evocation = _select_evocation(
				game,
				preferred,
				{
					"owner_id": caster_id,
					"archetype": str(effect.get("evocation_archetype", "")),
					"alive": true,
					"in_play": true
				},
				allow_auto_select
			)

			if evocation == null:
				# Explicit invalid selection fails. No available optional target succeeds.
				return preferred == null

			bonus = int(effect.get("strength_bonus", 0))

		"activate_target_evocation":
			evocation = context.get("target_evocation")
			if evocation != null:
				controller_id = evocation.owner_id
			bonus = int(
				context.get("pending_evocation_activation_strength_bonus", 0)
			)

		"activate_target_evocation_under_control":
			evocation = context.get("target_evocation")
			controller_id = caster_id
			bonus = int(effect.get("strength_bonus", 0))

	if evocation == null:
		return false

	var activation_context: Dictionary = context
	if effect.has("speed_bonus"):
		activation_context = context.duplicate(true)
		activation_context["evocation_activation_speed_bonus"] = int(effect["speed_bonus"])

	var success = _activate_evocation(
		evocation,
		controller_id,
		activation_context,
		bonus
	)

	if success and mode == "activate_target_evocation":
		context["pending_evocation_activation_strength_bonus"] = 0

	return success


# =============================================================================
# GROUPED DAMAGE VARIANTS
# =============================================================================

func _resolve_damage_variant(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if game == null:
		return false

	match mode:
		"damage_triggering_model":
			return _damage_trigger_model(
				game,
				caster_id,
				int(effect.get("amount", 0)),
				context
			)

		"damage_triggering_model_from_trigger_damage":
			var suffered = int(context.get("trigger_damage_amount", 0))
			var bonus = int(effect.get("bonus", 0))
			var amount = suffered + bonus
			if amount <= 0:
				return true

			var success = _damage_trigger_model(
				game,
				caster_id,
				amount,
				context
			)
			if success:
				print(
					"Torment retaliation: ", suffered,
					" suffered + ", bonus,
					" = ", amount, " damage"
				)
			return success

		"damage_from_evocation":
			if _is_dummy_target(context):
				return true

			var evocation = context.get("target_evocation")
			if evocation == null:
				return false

			var room_id: String = str(evocation.room_id)
			if room_id == "":
				return false

			var amount = (
				int(effect.get("base_amount", 0))
				+ evocation.get_damage()
				* int(effect.get("bonus_per_evocation_damage", 0))
			)

			if amount <= 0:
				return true

			var room_context: Dictionary = context.duplicate(false)
			room_context["spell_target_type"] = "room"
			room_context["target_room_id"] = room_id
			room_context.erase("target_player_index")
			room_context.erase("target_model_type")

			return _resolve_damage(
				{
					"type": "damage",
					"amount": amount,
					"target": "room"
				},
				room_context
			)

		"damage_all_target_owner_evocations":
			var target = int(
				context.get("last_damage_target_player_index", -1)
			)
			if not _valid_player(game, target):
				return false

			var amount = int(effect.get("amount", 0))
			for evocation in game.players[target].evocations.duplicate():
				_damage_evocation(game, caster_id, evocation, amount)
			return true

		"damage_marked_mage":
			var target = int(context.get("marked_player_index", -1))
			if not _valid_player(game, target):
				return false

			_damage_mage(
				game,
				caster_id,
				target,
				int(effect.get("amount", 0)),
				"spell"
			)
			return true

		"pain_from_trigger_damage":
			if not _valid_player(game, caster_id):
				return false
			var amount = int(context.get("trigger_damage_amount", 0))
			if amount > 0:
				game.deal_damage(-1, caster_id, amount, "spell")
			return true

		"damage_all_models_of_type":
			var amount = int(effect.get("amount", 0))
			if amount <= 0:
				return true

			var model_type = str(effect.get("model_type", ""))
			if model_type != "mage" and model_type != "evocation":
				return false

			var room_id: String = _target_room(context)
			var global_scope: bool = effect.get("scope", "room") == "lodge"
			if not global_scope and room_id == "":
				print("damage_all_models_of_type: target Room missing")
				return false

			var active_count = min(game.player_count, game.players.size())

			if model_type == "mage":
				for player_index in range(active_count):
					if game.is_mage_in_cell(player_index):
						continue

					if not global_scope and game.players[player_index].mage.room_id != room_id:
						continue

					var dealt = _damage_mage(
						game,
						caster_id,
						player_index,
						amount
					)

					if dealt > 0:
						register_damaged_model(
							context,
							{
								"type": "mage",
								"player_index": player_index,
								"room_id": game.players[player_index].mage.room_id
							}
						)

				return true

			for player_index in range(active_count):
				for evocation in game.players[player_index].evocations.duplicate():
					if evocation == null \
					or evocation.is_defeated() \
					or (not global_scope and evocation.room_id != room_id):
						continue

					var dealt = _damage_evocation(
						game,
						caster_id,
						evocation,
						amount
					)

					if dealt > 0:
						register_damaged_model(
							context,
							{
								"type": "evocation",
								"evocation": evocation,
								"room_id": evocation.room_id
							}
						)

			return true

		"damage_models_damaged_by_effect":
			if not _valid_player(game, caster_id):
				return false

			var amount = int(effect.get("amount", 1))
			if amount <= 0:
				return true

			var models: Array = context.get(
				"models_damaged_by_effect",
				[]
			).duplicate()

			for model in models:
				var model_type = str(model.get("type", ""))

				if model_type == "mage":
					var target = int(model.get("player_index", -1))
					if _valid_player(game, target):
						_damage_mage(game, caster_id, target, amount)

				elif model_type == "evocation":
					var evocation = model.get("evocation")
					if evocation != null \
					and _evocation_in_play(game, evocation) \
					and not evocation.is_defeated():
						_damage_evocation(game, caster_id, evocation, amount)

			return true

	return false


# =============================================================================
# TRIGGERS / FLOW / TARGETING
# =============================================================================

func _resolve_conditional(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var condition: String = str(
		effect.get("condition", "")
	)

	var condition_met: bool = false

	match condition:

		"last_damage_defeated_target":

			condition_met = bool(
				context.get(
					"last_damage_defeated_target",
					false
				)
			)


		"target_evocation_health_at_most":
			var target_evocation = context.get("target_evocation", null)
			condition_met = (
				target_evocation != null
				and int(target_evocation.health) <= int(effect.get("value", 0))
			)

		"caster_defeated_by_last_black_rose_damage":

			var caster_id: int = _caster(
				context
			)

			var last_target: int = int(
				context.get(
					"last_damage_target_player_index",
					-1
				)
			)

			var last_source: String = str(
				context.get(
					"last_damage_source_model_type",
					""
				)
			)

			var last_damage: int = int(
				context.get(
					"last_damage_dealt",
					0
				)
			)

			var defeated: bool = bool(
				context.get(
					"last_damage_defeated_target",
					false
				)
			)

			condition_met = (
				caster_id >= 0
				and last_target == caster_id
				and last_source == "black_rose"
				and last_damage > 0
				and defeated
			)


		_:

			print(
				"UNKNOWN CONDITION: ",
				condition
			)

			return false


	if condition_met:

		return resolve_effects(
			effect.get(
				"effects",
				[]
			),
			context
		)


	return resolve_effects(
		effect.get(
			"else_effects",
			[]
		),
		context
	)



# GEOMANCY_GEOFORM_V1
func _resolve_geoform(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	if game == null:
		return false

	var room_id: String = _target_room(context)
	if room_id == "":
		print("Geoform: target Room missing")
		return false

	var room_data = game.get_room(room_id)
	if room_data == null or not room_data is Dictionary:
		print("Geoform: Room not found: ", room_id)
		return false

	var room_color: String = str(room_data.get("color", ""))
	var allowed_colors: Array[String] = []
	for color_value in effect.get("room_colors", []):
		allowed_colors.append(str(color_value))

	if allowed_colors.is_empty():
		print("Geoform: no Room colors configured")
		return false

	context["last_geoform_room_id"] = room_id
	context["last_geoform_room_color"] = room_color
	context["last_geoform_active"] = allowed_colors.has(room_color)

	if not bool(context["last_geoform_active"]):
		return true

	return resolve_effects(
		effect.get("effects", []),
		context
	)


func _resolve_redirect_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	var event = context.get("trigger_event")

	if event == null or not _valid_player(game, caster_id):
		return false

	var player = game.players[caster_id]
	if player.evocations.is_empty():
		print("Pain Mark: no Evocation available to redirect Damage")
		return true

	var evocation = context.get(
		"selected_evocation_to_redirect",
		null
	)

	if evocation == null:
		# A single legal option may have been auto-selected by the Game
		# preflight. If no legal Evocation exists, the Effect simply has
		# nothing to redirect to.
		if player.evocations.size() == 1:
			evocation = player.evocations[0]
		else:
			print("Pain Mark: Evocation selection required")
			return false

	if not evocation in player.evocations:
		print("Pain Mark: selected Evocation is not owned by caster")
		return false

	event.redirected_evocation = evocation

	print(
		"Pain Mark redirects ", event.amount,
		" Damage from Player ", caster_id + 1,
		" to ", evocation.evocation_name
	)
	return true


func _resolve_gain_power_from_defeat(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	var event = context.get("trigger_event")

	if event == null or game == null:
		return false

	var amount = int(
		effect.get(
			"black_rose_amount" if event.source_model_type == "black_rose" else "mage_amount",
			2 if event.source_model_type == "black_rose" else 1
		)
	)

	if amount > 0:
		game.add_player_power(caster_id, amount)
	return true



# CAPUT_DRACONIS_V1
func _caput_direct_target_is_ignored(context: Dictionary) -> bool:
	var target_type: String = _target_type(context)
	if target_type != "mage" and target_type != "model":
		return false

	if target_type == "model":
		var model_type: String = str(context.get("target_model_type", ""))
		if model_type != "" and model_type != "mage":
			return false

	var player_index: int = int(context.get("target_player_index", -1))
	if player_index < 0:
		return false
	return DeathEffectResolver.ignores(context, player_index)


func _resolve_ignore_trigger_spell_effect(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var event = context.get("trigger_event")
	if event == null:
		print("Caput Draconis: trigger event missing")
		return false

	if not event.has_meta("caput_spell_effect"):
		print("Caput Draconis: source Spell Effect context missing")
		return false

	# Caput Draconis excludes Forgotten; Quicksand protects from any Combat Spell.
	if bool(event.get_meta("source_spell_forgotten", false)) and not bool(effect.get("include_forgotten", false)):
		print("Caput Draconis: source Spell is Forgotten; Effect is not ignored")
		return true

	var source_context_value = event.get_meta("source_spell_context", null)
	if not source_context_value is Dictionary:
		print("Caput Draconis: invalid source Spell context")
		return false
	var source_context: Dictionary = source_context_value

	var protected_player: int = _caster(context)
	if protected_player < 0:
		return false

	var ignored: Array = source_context.get("ignored_spell_players", [])
	if not ignored.has(protected_player):
		ignored.append(protected_player)
		source_context["ignored_spell_players"] = ignored

	context["caput_ignored_spell_id"] = str(event.get_meta("source_spell_id", ""))
	context["caput_ignored_player_index"] = protected_player

	print(
		"Caput Draconis: Player ",
		protected_player + 1,
		" ignores the non-Forgotten Spell Effect of ",
		str(event.get_meta("source_spell_id", ""))
	)
	return true


func _resolve_ignore_trigger_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var event = context.get("trigger_event")
	if event == null:
		print("ignore_trigger_damage: trigger event missing")
		return false

	var limit = int(effect.get("amount", 0))
	if limit <= 0:
		return true

	var original = int(event.amount)
	var ignored = min(limit, original)
	event.amount = max(0, original - ignored)
	context["silver_damage_ignored"] = ignored

	print(
		"Ignored ", ignored,
		" Damage | ", original,
		" -> ", event.amount
	)
	return true


func _resolve_modify_spell_target(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var target = str(effect.get("target", ""))
	if target == "":
		return false

	context["spell_target_type"] = target
	if effect.has("range"):
		context["spell_range"] = effect["range"]

	print(
		"Spell target changed to ", target,
		" | Range: ", context.get("spell_range", null)
	)
	return true


func _resolve_move_damaged_model(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	if game == null:
		return false

	var models: Array = context.get("models_damaged_by_effect", [])
	if models.is_empty():
		return true

	var index = int(context.get("damaged_model_to_move_index", -1))
	var destination = str(context.get("movement_destination_room_id", ""))

	if index < 0 or index >= models.size():
		print("Deflagrate: damaged Model selection required")
		return false
	if destination == "":
		print("Deflagrate: movement destination required")
		return false

	var model = models[index]
	var distance = int(effect.get("distance", 1))
	# Choosing the current Room ends movement without emitting a room-entry event.
	if destination == game._damaged_model_room_id(context, index):
		return true

	if str(model.get("type", "")) == "mage":
		return game.move_mage_to_room_id(
			int(model.get("player_index", -1)),
			destination,
			distance
		)

	if str(model.get("type", "")) == "evocation":
		var evocation = model.get("evocation")
		if evocation == null:
			return false
		return game.move_evocation_to_room_id(
			evocation,
			destination,
			distance
		)

	return false



# WHIPS_OF_THORNS_V1
func _whips_choice_first(value):
	if value is Array:
		if value.is_empty():
			return null
		return value[0]
	return value


func _resolve_damage_rooms_in_range_from_target(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var origin_room_id: String = _target_room(context)
	if origin_room_id == "":
		print("damage_rooms_in_range_from_target: target Room missing")
		return false

	var amount: int = maxi(0, int(effect.get("amount", 0)))
	var max_distance: int = maxi(
		0,
		int(effect.get("range_from_target", 0))
	)

	if amount <= 0:
		return true

	if not context.has("models_damaged_by_effect"):
		context["models_damaged_by_effect"] = []

	var seen_rooms: Dictionary = {}

	for room_value in game.room_id_by_coord.values():
		var room_id: String = str(room_value)

		if seen_rooms.has(room_id):
			continue
		seen_rooms[room_id] = true

		if not game.is_room_within_effect_range(
			origin_room_id,
			room_id,
			max_distance
		):
			continue

		for player_index in range(game.players.size()):
			if game.is_mage_in_cell(player_index):
				continue

			var mage = game.players[player_index].mage
			if mage == null or str(mage.room_id) != room_id:
				continue

			var dealt: int = _damage_mage(
				game,
				caster_id,
				player_index,
				amount
			)

			if dealt > 0:
				register_damaged_model(
					context,
					{
						"type": "mage",
						"player_index": player_index,
						"room_id": room_id
					}
				)

		for player in game.players:
			for evocation in player.evocations.duplicate():
				if evocation == null:
					continue
				if evocation.is_defeated():
					continue
				if str(evocation.room_id) != room_id:
					continue

				var dealt: int = _damage_evocation(
					game,
					caster_id,
					evocation,
					amount
				)

				if dealt > 0:
					register_damaged_model(
						context,
						{
							"type": "evocation",
							"evocation": evocation,
							"room_id": room_id
						}
					)

	context["last_area_damage_origin_room_id"] = origin_room_id
	context["last_area_damage_range"] = max_distance
	context["last_area_damage_amount"] = amount

	return true


func _resolve_move_model_near_target_room(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	var caster := _caster(context)
	var origin := _target_room(context)
	if game == null or origin.is_empty():
		return false
	var model_key := "_near_room_model"
	var destination_key := "_near_room_destination"
	var distance := int(effect.get("distance", 1))
	if not context.has(model_key):
		var options: Array = []
		for option in game._quest_model_choice_options(caster, {"range":"*", "include_self":true}):
			if game.get_hex_distance(game.room_id_to_coord(origin), game.room_id_to_coord(str(option.room_id))) > int(effect.get("model_range", 1)):
				continue
			if option.value.type == "mage" and DeathEffectResolver.ignores(context, int(option.value.player_index)):
				continue
			options.append(option)
		if options.is_empty():
			return true
		game.request_effect_choice(caster, "model", context, model_key, options, 0, 1,
			"Move up to 1: choose a Model within 1 Room of the target Room, or skip.")
		return false
	var model = context[model_key]
	if model == null:
		context.erase(model_key)
		return true
	var from_room: String = game.players[int(model.player_index)].mage.room_id if model.type == "mage" else model.evocation.room_id
	if not context.has(destination_key):
		var options: Array = game._quest_room_choice_options(caster, {"range":distance}, from_room)
		game.request_effect_choice(caster, "secondary_room", context, destination_key, options, 1, 1,
			"Move the selected Model up to 1 Room. Select its current Room to stay.")
		return false
	var destination: String = str(context[destination_key])
	context.erase(model_key)
	context.erase(destination_key)
	if destination == from_room:
		return true
	if model.type == "mage":
		return game.move_mage_to_room_id(int(model.player_index), destination, distance)
	return game.move_evocation_to_room_id(model.evocation, destination, distance)


func _resolve_move_one_mage_in_target_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var target_room_id: String = _target_room(context)
	if target_room_id == "":
		print("move_one_mage_in_target_room: target Room missing")
		return false

	var distance: int = maxi(
		0,
		int(effect.get("distance", 1))
	)
	var optional: bool = bool(effect.get("optional", true))

	var mage_choice_key: String = str(
		effect.get(
			"mage_choice_key",
			"_whips_selected_mage"
		)
	)
	var destination_choice_key: String = str(
		effect.get(
			"destination_choice_key",
			"_whips_mage_destination_room"
		)
	)

	if not context.has(mage_choice_key):
		var mage_options: Array = []

		for player_index in range(game.players.size()):
			if game.is_mage_in_cell(player_index):
				continue
			if DeathEffectResolver.ignores(context, player_index):
				continue

			var mage = game.players[player_index].mage
			if mage == null or str(mage.room_id) != target_room_id:
				continue

			mage_options.append({
				"token": "mage:whips:" + str(player_index),
				"value": player_index,
				"player_index": player_index,
				"target_type": "mage",
				"name": "Player " + str(player_index + 1)
			})

		if mage_options.is_empty():
			return true

		var min_select: int = 0 if optional else 1

		if not game.request_effect_choice(
			caster_id,
			"mage",
			context,
			mage_choice_key,
			mage_options,
			min_select,
			1,
			"Choose a Mage in the target Room to move"
			+ (" (optional)." if optional else ".")
		):
			return false

		return false

	var selected_mage_value = _whips_choice_first(
		context.get(mage_choice_key, null)
	)

	if selected_mage_value == null or str(selected_mage_value) == "":
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		return true

	var selected_player_index: int
	if selected_mage_value is Dictionary:
		selected_player_index = int(
			selected_mage_value.get("player_index", -1)
		)
	else:
		selected_player_index = int(selected_mage_value)

	if not _valid_player(game, selected_player_index):
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		return false

	if DeathEffectResolver.ignores(context, selected_player_index):
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		return true

	var selected_mage = game.players[selected_player_index].mage
	if selected_mage == null \
	or game.is_mage_in_cell(selected_player_index) \
	or str(selected_mage.room_id) != target_room_id:
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		print(
			"move_one_mage_in_target_room: "
			+ "selected Mage is no longer in the target Room"
		)
		return false

	if not context.has(destination_choice_key):
		var from_coord: Vector2i = game.room_id_to_coord(
			target_room_id
		)
		var room_options: Array = []
		var seen_rooms: Dictionary = {}

		for room_value in game.room_id_by_coord.values():
			var destination_room_id: String = str(room_value)

			if seen_rooms.has(destination_room_id):
				continue
			seen_rooms[destination_room_id] = true

			if destination_room_id == target_room_id:
				continue

			var to_coord: Vector2i = game.room_id_to_coord(
				destination_room_id
			)

			if from_coord == Vector2i(9999, 9999) \
			or to_coord == Vector2i(9999, 9999):
				continue

			if game.get_hex_distance(
				from_coord,
				to_coord
			) > distance:
				continue

			var destination_room = game.get_room_by_id(
				destination_room_id
			)
			var room_name: String = destination_room_id
			if destination_room != null:
				room_name = str(destination_room.room_name)

			room_options.append({
				"token":
					"room:whips_movement:"
					+ destination_room_id,
				"value": destination_room_id,
				"room_id": destination_room_id,
				"target_type": "room",
				"name": room_name
			})

		if room_options.is_empty():
			context.erase(mage_choice_key)
			context.erase(destination_choice_key)
			return true

		var destination_min_select: int = 0 if optional else 1

		if not game.request_effect_choice(
			caster_id,
			"secondary_room",
			context,
			destination_choice_key,
			room_options,
			destination_min_select,
			1,
			"Choose where to move Player "
			+ str(selected_player_index + 1)
			+ " (up to "
			+ str(distance)
			+ ")."
		):
			return false

		return false

	var destination_value = _whips_choice_first(
		context.get(destination_choice_key, null)
	)

	if destination_value == null or str(destination_value) == "":
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		return true

	var destination_room_id: String
	if destination_value is Dictionary:
		destination_room_id = str(
			destination_value.get("room_id", "")
		)
	else:
		destination_room_id = str(destination_value)

	if destination_room_id == "":
		context.erase(mage_choice_key)
		context.erase(destination_choice_key)
		return false

	var success: bool = game.move_mage_to_room_id(
		selected_player_index,
		destination_room_id,
		distance
	)

	context.erase(mage_choice_key)
	context.erase(destination_choice_key)

	if success:
		context["last_moved_mage_player_index"] = (
			selected_player_index
		)
		context["last_moved_mage_destination_room_id"] = (
			destination_room_id
		)

	return success


func _resolve_activate_room_from_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var room_id = str(context.get("target_room_id", ""))
	if room_id == "":
		return false

	var excluded: Array = effect.get("excluded_rooms", [])
	if room_id in excluded:
		return false

	var archetype = str(effect.get("evocation_archetype", ""))
	if archetype == "":
		return false

	if not game._spell_room_target_allowed(caster_id, {"effects": [effect]}, room_id):
		return false

	return game.activate_room(caster_id, room_id, bool(effect.get("allow_used_room", false)),
		{"effect_origin_room_id": room_id})


# =============================================================================
# COMPOSITE / CHOICE EFFECTS
# =============================================================================

func _resolve_remove_and_damage_around(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	var evocation = context.get("target_evocation")

	if not _valid_player(game, caster_id) or evocation == null:
		return false
	if evocation.owner_id != caster_id:
		return false
	if not _evocation_in_play(game, evocation):
		return false

	var room_id = str(evocation.room_id)
	var name = str(evocation.evocation_name)

	if not _remove_evocation(game, evocation, context, false):
		return false

	print("Liquid Fire: removed ", name, " from ", room_id)

	return _damage_within_distance(
		game,
		caster_id,
		room_id,
		int(effect.get("distance", 1)),
		int(effect.get("damage", 2)),
		context
	)


func _resolve_choice_effect(
	effect: Dictionary,
	context: Dictionary,
	mode: String
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	if mode == "fountain_construct_or_nigredo":
		var room_id = str(context.get("target_room_id", ""))
		if room_id == "":
			return false

		var choice = str(context.get("fountain_choice", ""))

		if choice == "summon_nigredo":
			return _summon(
				game,
				caster_id,
				"nigredo",
				room_id,
				context
			) != null

		if choice == "activate_construct":
			var construct = _select_evocation(
				game,
				context.get("selected_evocation_to_activate"),
				{
					"archetype": "construct",
					"room_id": room_id,
					"alive": true,
					"in_play": true
				},
				true
			)
			if construct == null:
				return false
			return _activate_evocation(
				construct,
				caster_id,
				context
			)

		return false

	# Silver of the Sages Dark.
	var choice = str(context.get("silver_choice", ""))

	if choice == "summon_nigredo":
		var room_id = str(context.get("trigger_evocation_room_id", ""))
		if room_id == "":
			room_id = game.players[caster_id].mage.room_id

		return _summon(
			game,
			caster_id,
			"nigredo",
			room_id,
			context
		) != null

	if choice == "activate_construct":
		var construct = _select_evocation(
			game,
			context.get("selected_evocation_to_activate"),
			{
				"owner_id": caster_id,
				"archetype": "construct",
				"alive": true,
				"in_play": true
			},
			true
		)
		if construct == null:
			return false
		return _activate_evocation(
			construct,
			caster_id,
			context
		)

	return false


func _resolve_heal_target_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	if _is_dummy_target(context):
		return true

	var game = _game(context)
	var caster_id = _caster(context)
	var evocation = context.get("target_evocation")

	if game == null or evocation == null:
		return false

	if str(effect.get("owner", "")) == "caster" \
	and evocation.owner_id != caster_id:
		return false

	if evocation.is_defeated():
		return false

	var healed = _heal_evocation(
		game,
		evocation,
		int(effect.get("amount", 0))
	)

	print(
		"Purifying Aludel: healed ", healed,
		" Damage from ", evocation.evocation_name,
		" | HP: ", evocation.get_remaining_health(),
		"/", evocation.health
	)
	return true


func _resolve_next_activation_strength_bonus(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	if _is_dummy_target(context):
		return true

	if context.get("target_evocation") == null:
		return false

	context["pending_evocation_activation_strength_bonus"] = int(
		effect.get("amount", 0)
	)
	return true


func _resolve_activate_then_black_rose_damage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	var game = _game(context)
	var caster_id = _caster(context)
	if not _valid_player(game, caster_id):
		return false

	var evocation = _select_evocation(
		game,
		context.get("selected_evocation_to_activate"),
		{
			"owner_id": caster_id,
			"alive": true,
			"in_play": true
		},
		true
	)

	if evocation == null:
		return false

	var amount = int(effect.get("amount", 1))

	# queue_resolution() is LIFO. Queue the post-activation Damage first, then
	# the activation, so the Evocation completes its activation before the
	# Black Rose Damage is resolved.
	game.deal_damage_to_evocation(-1, evocation, amount)

	if not _activate_evocation(evocation, caster_id, context):
		return false

	print(
		"Silver of the Sages: Black Rose inflicts ",
		amount,
		" Damage to ", evocation.evocation_name
	)
	return true


# CONTORTION_V1
func resolve_set_target_mage_from_triggering_mage(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if _is_dummy_target(context):
		return true

	var game = _game(context)
	if game == null:
		return false

	var player_index: int = int(
		context.get("triggering_player_index", -1)
	)

	if not _valid_player(game, player_index):
		print(
			"set_target_mage_from_triggering_mage: "
			+ "triggering Mage missing"
		)
		return false

	context["target_player_index"] = player_index
	context["target_model_type"] = "mage"
	context["spell_target_type"] = "mage"

	var room_id: String = str(
		context.get("triggering_room_id", "")
	)
	if room_id != "":
		context["target_room_id"] = room_id

	return true


func _resolve_steal_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var target_player_index: int = int(
		context.get("target_player_index", -1)
	)
	if not _valid_player(game, target_player_index):
		print("steal_power: target Mage missing")
		return false

	if DeathEffectResolver.ignores(context, target_player_index) \
	or (target_player_index != caster_id and game.is_mage_in_cell(target_player_index)):
		context["last_power_stolen"] = 0
		return true

	var amount: int = maxi(
		0,
		int(effect.get("amount", 0))
	)
	if amount <= 0:
		return true

	var available: int = maxi(
		0,
		int(game.players[target_player_index].power)
	)
	var stolen: int = mini(amount, available)

	if stolen <= 0:
		context["last_power_stolen"] = 0
		return true

	game.add_player_power(
		target_player_index,
		-stolen
	)
	game.add_player_power(
		caster_id,
		stolen
	)

	context["last_power_stolen"] = stolen
	context["last_power_stolen_from"] = target_player_index

	print(
		"Steal Power: Player ",
		caster_id + 1,
		" stole ",
		stolen,
		" Power from Player ",
		target_player_index + 1
	)

	return true


func _resolve_activate_target_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)

	if game == null or not _valid_player(game, caster_id):
		return false

	var room_id: String = _target_room(context)
	if room_id == "":
		print("activate_target_room: target Room missing")
		return false

	var allow_reactivate: bool = bool(
		effect.get("allow_reactivate", false)
	)

	return game.activate_room(
		caster_id,
		room_id,
		allow_reactivate,
		context
	)


func resolve_set_target_room_from_triggering_mage(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	if _is_dummy_target(context):
		return true

	var game = _game(context)
	if game == null:
		return false

	var player_index: int = int(
		context.get("triggering_player_index", -1)
	)
	if not _valid_player(game, player_index):
		print(
			"set_target_room_from_triggering_mage: "
			+ "triggering Mage missing"
		)
		return false

	var room_id: String = str(
		context.get("triggering_room_id", "")
	)
	if room_id == "":
		print(
			"set_target_room_from_triggering_mage: "
			+ "triggering Mage Room missing"
		)
		return false

	context["target_room_id"] = room_id
	context["target_player_index"] = player_index
	context["target_model_type"] = "mage"

	return true


func resolve_set_target_room_from_target_evocation(
	effect: Dictionary,
	context: Dictionary
) -> bool:

	if _is_dummy_target(context):
		return true

	var target_evocation = context.get(
		"target_evocation"
	)

	if target_evocation == null:
		print(
			"set_target_room_from_target_evocation: "
			+ "target_evocation missing"
		)
		return false


	var room_id: String = str(
		target_evocation.room_id
	)


	if room_id == "":
		print(
			"set_target_room_from_target_evocation: "
			+ "target Evocation has no Room"
		)
		return false


	# Da questo momento gli effetti che lavorano
	# sulla Room useranno la Room della Evocation scelta.
	context["target_room_id"] = room_id


	print(
		"Target Room set from Evocation ",
		target_evocation.evocation_name,
		": ",
		room_id
	)


	return true

# =============================================================================
# CHAOS SCHOOL
# =============================================================================

func _chaos_target_room(context: Dictionary) -> String:
	var game = _game(context)
	if game == null:
		return ""
	if str(context.get("target_room_id", "")) != "":
		return str(context.get("target_room_id", ""))
	var target_evocation = context.get("target_evocation", null)
	if target_evocation != null:
		return str(target_evocation.room_id)
	var target_player_index: int = int(context.get("target_player_index", -1))
	if _valid_player(game, target_player_index):
		return str(game.players[target_player_index].mage.room_id)
	return ""


func _vastum_room_choice_options(
	game,
	caster_id: int,
	effect: Dictionary,
	context: Dictionary
) -> Array:
	var result: Array = []
	if game == null or not _valid_player(game, caster_id):
		return result

	var origin_mode: String = str(effect.get("origin", "caster"))
	var origin_room_id: String = str(game.players[caster_id].mage.room_id)
	if origin_mode == "target":
		origin_room_id = _chaos_target_room(context)

	var range_value = effect.get("range", "*")
	var excluded_room_id: String = ""
	if bool(effect.get("exclude_target_room", false)):
		excluded_room_id = _chaos_target_room(context)
	var exclude_origin_room: bool = bool(effect.get("exclude_origin_room", false))

	for room_value in game.room_id_by_coord.values():
		var room_id: String = str(room_value)
		if room_id == excluded_room_id:
			continue
		if exclude_origin_room and room_id == origin_room_id:
			continue
		if origin_room_id != "" and not game.is_room_within_effect_range(
			origin_room_id,
			room_id,
			range_value
		):
			continue
		var room = game.get_room_by_id(room_id)
		result.append({
			"token": "vastum_room:" + room_id,
			"value": room_id,
			"room_id": room_id,
			"name": str(room.room_name) if room != null else room_id
		})

	return result


func _choice_option_available(
	option: Dictionary,
	context: Dictionary
) -> bool:
	var requirements = option.get("requires", {})
	if not requirements is Dictionary or requirements.is_empty():
		return true

	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null:
		return false

	if bool(requirements.get("target_room_has_vastum", false)):
		if not game.room_has_vastum(_chaos_target_room(context)):
			return false

	if requirements.has("lodge_vastum_at_least"):
		if game.count_vastum() < int(requirements.get("lodge_vastum_at_least", 0)):
			return false

	if bool(requirements.get("active_quest_available", false)):
		if not _valid_player(game, caster_id) or game.players[caster_id].active_quests.is_empty():
			return false

	if requirements.has("caster_power_at_least"):
		if not _valid_player(game, caster_id) \
		or int(game.players[caster_id].power) < int(requirements.get("caster_power_at_least", 0)):
			return false

	if requirements.has("vastum_room_choice_available"):
		var spec = requirements.get("vastum_room_choice_available", {})
		if not spec is Dictionary:
			return false
		if _vastum_room_choice_options(game, caster_id, spec, context).is_empty():
			return false

	return true


func _resolve_choose_one(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var choice_key: String = str(effect.get("choice_key", "chaos_branch"))
	if not context.has(choice_key):
		var options: Array = []
		for option_value in effect.get("options", []):
			if not option_value is Dictionary:
				continue
			var option: Dictionary = option_value
			if not _choice_option_available(option, context):
				continue
			var option_id: String = str(option.get("id", ""))
			if option_id == "":
				continue
			options.append({
				"token": "branch:" + choice_key + ":" + option_id,
				"value": option_id,
				"name": str(option.get("label", option_id.capitalize()))
			})
		if options.is_empty():
			return true
		game.request_effect_choice(
			caster_id,
			"chaos_branch",
			context,
			choice_key,
			options,
			1,
			1,
			str(effect.get("prompt", "Choose one Effect."))
		)
		return false

	var selected_id: String = str(context.get(choice_key, ""))
	for option_value in effect.get("options", []):
		if not option_value is Dictionary:
			continue
		var option: Dictionary = option_value
		if str(option.get("id", "")) != selected_id:
			continue
		var nested_effects: Array = option.get("effects", [])
		context.erase(choice_key)
		if nested_effects.is_empty():
			return true
		game.queue_resolution({
			"type": "effect_sequence",
			"resolver_kind": str(context.get("resolver_kind", "spell")),
			"effects": nested_effects,
			"index": 0,
			"context": context
		})
		return true

	context.erase(choice_key)
	return false


func _resolve_place_vastum(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var room_source: String = str(effect.get("room_source", "target"))
	var room_id: String = ""

	match room_source:
		"target":
			room_id = str(context.get("target_room_id", ""))
		"caster":
			room_id = str(game.players[caster_id].mage.room_id)
		"target_model":
			room_id = _chaos_target_room(context)
		"choose":
			var choice_key: String = str(effect.get("choice_key", "vastum_room"))
			if not context.has(choice_key):
				var options: Array = _vastum_room_choice_options(
					game,
					caster_id,
					effect,
					context
				)
				if options.is_empty():
					return true
				game.request_effect_choice(
					caster_id,
					"vastum_room",
					context,
					choice_key,
					options,
					1,
					1,
					"Choose the Room for the Vastum."
				)
				return false
			room_id = str(context.get(choice_key, ""))
			context.erase(choice_key)
		_:
			return false

	if room_id == "" or not game.is_lodge_room_id(room_id):
		return false

	context["effect_target_room_id"] = room_id
	# The Chaos rule explicitly says the Effect still resolves if that Room
	# already contains a Vastum; only the placement is ignored.
	game.place_vastum(room_id)
	return true


func _resolve_remove_vastum(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	if game == null:
		return false
	var room_source: String = str(effect.get("room_source", "target"))
	var room_id: String = ""
	if room_source == "target":
		room_id = _chaos_target_room(context)
	elif room_source == "caster":
		var caster_id: int = _caster(context)
		if _valid_player(game, caster_id):
			room_id = str(game.players[caster_id].mage.room_id)
	if room_id == "":
		return false
	context["effect_target_room_id"] = room_id
	return game.remove_vastum(room_id)


func _resolve_remove_vastum_from_lodge(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var amount: int = maxi(0, int(effect.get("amount", 1)))
	if amount == 0:
		return true
	var choice_key: String = str(effect.get("choice_key", "vastum_remove_rooms"))
	if not context.has(choice_key):
		var options: Array = []
		for room_id_value in game.get_vastum_room_ids():
			var room_id: String = str(room_id_value)
			var room = game.get_room_by_id(room_id)
			options.append({
				"token": "remove_vastum:" + room_id,
				"value": room_id,
				"room_id": room_id,
				"name": str(room.room_name) if room != null else room_id
			})
		if options.size() < amount:
			return false
		game.request_effect_choice(
			caster_id,
			"remove_vastum",
			context,
			choice_key,
			options,
			amount,
			amount,
			"Choose %d Vastum to remove." % amount
		)
		return false

	var selected: Array = _choice_as_array(context.get(choice_key))
	if selected.size() != amount:
		return false
	for room_id_value in selected:
		if not game.room_has_vastum(str(room_id_value)):
			return false
	for room_id_value in selected:
		game.remove_vastum(str(room_id_value))
	context.erase(choice_key)
	return true


func _resolve_damage_equal_vastum_count(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	if game == null:
		return false
	var amount: int = mini(
		game.count_vastum(),
		int(effect.get("max", 999))
	)
	if amount <= 0:
		return true
	return _resolve_damage(
		{"type": "damage", "amount": amount},
		context
	)


func _target_model_room(context: Dictionary) -> String:
	return _chaos_target_room(context)


func _resolve_move_target_up_to(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if _is_dummy_target(context):
		return true
	var target_evocation: EvocationState = context.get("target_evocation")
	if target_evocation != null and target_evocation.archetype == "equipment":
		return true
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var target_id: int = int(context.get("target_player_index", -1))
	if str(context.get("target_model_type", "mage")) == "mage" \
	and target_id != caster_id and game.is_mage_in_cell(target_id):
		return true
	var origin_room_id: String = _target_model_room(context)
	if origin_room_id == "":
		return false
	var distance: int = maxi(0, int(effect.get("distance", 1)))
	var choice_key: String = str(effect.get("choice_key", "move_target_destination"))
	if not context.has(choice_key):
		var options: Array = []
		for room_value in game.room_id_by_coord.values():
			var room_id: String = str(room_value)
			var origin_coord: Vector2i = game.room_id_to_coord(origin_room_id)
			var room_coord: Vector2i = game.room_id_to_coord(room_id)
			if origin_coord == Vector2i(9999, 9999) \
			or room_coord == Vector2i(9999, 9999) \
			or game.get_hex_distance(origin_coord, room_coord) > distance:
				continue
			var room = game.get_room_by_id(room_id)
			options.append({
				"token": "move_target:" + room_id,
				"value": room_id,
				"room_id": room_id,
				"name": ("Stay in " if room_id == origin_room_id else "Move to ") + (str(room.room_name) if room != null else room_id)
			})
		game.request_effect_choice(
			caster_id,
			"movement_destination",
			context,
			choice_key,
			options,
			1,
			1,
			"Move the target up to %d." % distance
		)
		return false
	var destination_room_id: String = str(context.get(choice_key, ""))
	context.erase(choice_key)
	if destination_room_id == origin_room_id:
		return true
	var model_type: String = str(context.get("target_model_type", ""))
	if model_type == "mage" or (model_type == "" and context.has("target_player_index")):
		return game.move_mage_to_room_id(
			int(context.get("target_player_index", -1)),
			destination_room_id,
			distance
		)
	if model_type == "evocation":
		return game.move_evocation_to_room_id(
			context.get("target_evocation", null),
			destination_room_id,
			distance
		)
	return false


func _resolve_memory_to_top_grimoire(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var player = game.players[caster_id]
	if player.memories.is_empty():
		return true
	var choice_key: String = str(effect.get("choice_key", "memory_to_top"))
	if not context.has(choice_key):
		var options: Array = []
		for i in range(player.memories.size()):
			var spell: SpellCardState = player.memories[i]
			options.append({
				"token": "memory_spell:%d" % i,
				"value": spell,
				"name": spell.card_name
			})
		game.request_effect_choice(caster_id, "memory_spell", context, choice_key, options, 1, 1, "Choose a Spell from your Memories.")
		return false
	var chosen: SpellCardState = context.get(choice_key, null)
	context.erase(choice_key)
	if chosen == null:
		return false
	var index: int = player.memories.find(chosen)
	if index < 0:
		return false
	player.memories.remove_at(index)
	player.grimoire.append(chosen)
	return true


func _resolve_search_grimoire_to_top(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var player = game.players[caster_id]
	if player.grimoire.is_empty():
		return true
	var choice_key: String = str(effect.get("choice_key", "grimoire_to_top"))
	if not context.has(choice_key):
		var options: Array = []
		for i in range(player.grimoire.size()):
			var spell: SpellCardState = player.grimoire[i]
			options.append({
				"token": "grimoire_spell:%d" % i,
				"value": spell,
				"name": spell.card_name
			})
		game.request_effect_choice(caster_id, "grimoire_spell", context, choice_key, options, 1, 1, "Search your Grimoire for a Spell to put on top.")
		return false
	var chosen: SpellCardState = context.get(choice_key, null)
	context.erase(choice_key)
	if chosen == null:
		return false
	var index: int = player.grimoire.find(chosen)
	if index < 0:
		return false
	player.grimoire.remove_at(index)
	game.shuffle_with_rng(player.grimoire)
	player.grimoire.append(chosen)
	return true


func _resolve_place_caster_in_target_room(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	# Works both for a Room primary target and for a Mage/Evocation target.
	var room_id: String = _chaos_target_room(context)
	if room_id == "":
		return false
	return _place_mage_direct(game, caster_id, room_id)


func _place_target_model_direct(
	game,
	context: Dictionary,
	room_id: String
) -> bool:
	if _is_dummy_target(context):
		return true
	if game == null or room_id == "":
		return false
	if str(context.get("spell_target_type", "")) == "self":
		return _place_mage_direct(game, int(context.get("caster_id", -1)), room_id)

	var model_type: String = str(context.get("target_model_type", ""))

	if model_type == "mage" \
	or (model_type == "" and context.has("target_player_index")):
		return _place_mage_direct(
			game,
			int(context.get("target_player_index", -1)),
			room_id
		)

	if model_type == "evocation":
		var evocation = context.get("target_evocation", null)
		if evocation == null:
			return false
		if evocation.archetype == "equipment":
			return true

		return game.place_evocation_in_room_direct(
			evocation,
			room_id
		)

	return false


func _resolve_place_target_in_caster_room(
	_effect: Dictionary,
	context: Dictionary
) -> bool:
	if _is_dummy_target(context):
		return true
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var room_id: String = str(game.players[caster_id].mage.room_id)
	if room_id == "":
		return false

	return _place_target_model_direct(game, context, room_id)


func _resolve_place_target_in_any_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if _is_dummy_target(context):
		return true
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var choice_key: String = str(
		effect.get("choice_key", "place_target_any_room")
	)

	if not context.has(choice_key):
		var options: Array = []

		for room_value in game.room_id_by_coord.values():
			var room_id: String = str(room_value)
			if effect.has("range_from_caster") and not game.is_room_within_effect_range(
				game.players[caster_id].mage.room_id, room_id, effect.range_from_caster):
				continue
			var room = game.get_room_by_id(room_id)
			options.append({
				"token": "place_target_any_room:" + room_id,
				"value": room_id,
				"room_id": room_id,
				"name": str(room.room_name) if room != null else room_id
			})

		if options.is_empty():
			return false

		game.request_effect_choice(
			caster_id,
			"movement_destination",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose the Room in which to place the target."
		)
		return false

	var room_id: String = str(context.get(choice_key, ""))
	context.erase(choice_key)

	if not game.is_lodge_room_id(room_id):
		return false

	return _place_target_model_direct(game, context, room_id)


func _resolve_place_caster_in_vastum_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false

	var choice_key: String = str(
		effect.get("choice_key", "caster_vastum_destination")
	)

	if not context.has(choice_key):
		var options: Array = []

		for room_id_value in game.get_vastum_room_ids():
			var room_id: String = str(room_id_value)
			var room = game.get_room_by_id(room_id)
			options.append({
				"token": "caster_vastum_destination:" + room_id,
				"value": room_id,
				"room_id": room_id,
				"name": str(room.room_name) if room != null else room_id
			})

		# The card says "may"; if no Vastum exists, there is simply no placement.
		if options.is_empty():
			return true

		game.request_effect_choice(
			caster_id,
			"vastum_destination",
			context,
			choice_key,
			options,
			1,
			1,
			"Choose a Room containing a Vastum."
		)
		return false

	var room_id: String = str(context.get(choice_key, ""))
	context.erase(choice_key)

	if not game.room_has_vastum(room_id):
		return false

	return _place_mage_direct(game, caster_id, room_id)


func _resolve_place_target_in_vastum_room(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	if _is_dummy_target(context):
		return true
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var choice_key: String = str(effect.get("choice_key", "vastum_destination"))
	if not context.has(choice_key):
		var options: Array = []
		for room_id_value in game.get_vastum_room_ids():
			var room_id: String = str(room_id_value)
			var room = game.get_room_by_id(room_id)
			options.append({
				"token": "vastum_destination:" + room_id,
				"value": room_id,
				"room_id": room_id,
				"name": str(room.room_name) if room != null else room_id
			})
		if options.is_empty():
			return true
		game.request_effect_choice(caster_id, "vastum_destination", context, choice_key, options, 1, 1, "Choose a Room containing a Vastum.")
		return false
	var room_id: String = str(context.get(choice_key, ""))
	context.erase(choice_key)
	if not game.room_has_vastum(room_id):
		return false
	return _place_target_model_direct(game, context, room_id)


func _resolve_lose_caster_power(
	effect: Dictionary,
	context: Dictionary
) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if game == null or not _valid_player(game, caster_id):
		return false
	var amount: int = maxi(0, int(effect.get("amount", 1)))
	if int(game.players[caster_id].power) < amount:
		return false
	game.add_player_power(caster_id, -amount)
	return true


func _resolve_chaos(effect: Dictionary, context: Dictionary) -> bool:
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not _valid_player(game, caster_id):
		return false
	var player = game.players[caster_id]
	var key: String = str(effect.get("key", "chaos"))
	var shuffle_key := key + "_shuffle_memories"
	var shuffle_applied_key := key + "_shuffle_applied"
	var room_key := key + "_room"
	var card_key := key + "_revealed_spell"
	var ack_key := key + "_reveal_ack"
	var all_key := key + "_all_choice"

	if not bool(context.get(shuffle_applied_key, false)):
		if not player.memories.is_empty() and not context.has(shuffle_key):
			game.request_effect_choice(caster_id, "chaos_shuffle", context, shuffle_key, [
				{"token": key + ":shuffle:no", "value": false, "name": "Keep Memories as they are"},
				{"token": key + ":shuffle:yes", "value": true, "name": "Shuffle Memories into your Grimoire"}
			], 1, 1, "Chaos: you may shuffle your Memories into your Grimoire.")
			return false
		if bool(context.get(shuffle_key, false)):
			game.shuffle_memories_into_grimoire(caster_id)
		context.erase(shuffle_key)
		context[shuffle_applied_key] = true

	if not context.has(room_key):
		var options: Array = []
		for room_id in game.get_vastum_room_ids():
			var room = game.get_room_by_id(room_id)
			options.append({"token": key + ":room:" + room_id, "value": room_id,
				"room_id": room_id, "name": str(room.room_name)})
		if options.is_empty():
			context.erase(shuffle_applied_key)
			return true
		game.request_effect_choice(caster_id, "chaos_room", context, room_key, options,
			1, 1, "Chaos: choose a Vastum.")
		return false

	# The revealed physical card stays in this resolution until its effect has
	# finished, including nested Room activations and their player decisions.
	# It is neither discarded nor available for drawing/shuffling in the meantime.
	if not context.has(card_key):
		if player.grimoire.is_empty():
			context.erase(room_key)
			context.erase(shuffle_applied_key)
			return true
		context[card_key] = player.grimoire.pop_back()
	var revealed: SpellCardState = context[card_key]
	if not bool(context.get(ack_key, false)):
		game.request_chaos_reveal_ack(caster_id, revealed, context, ack_key)
		return false

	var mode := "none"
	match str(revealed.light_side.get("element", "")).to_lower():
		"profane": mode = "damage"
		"sacred": mode = "instability"
		"magic": mode = "activate_room"
		"all", "any", "wild", "wildcard", "all_elements":
			if not context.has(all_key):
				game.request_effect_choice(caster_id, "chaos_all_element", context, all_key, [
					{"token": key + ":all:damage", "value": "damage", "name": "Inflict 2 Damage"},
					{"token": key + ":all:instability", "value": "instability", "name": "Place 1 Instability"},
					{"token": key + ":all:activate", "value": "activate_room", "name": "Activate the Room"}
				], 1, 1, "Chaos: choose one of the three wildcard effects.")
				return false
			mode = str(context[all_key])

	var room_id: String = str(context[room_key])
	for temporary_key in [shuffle_applied_key, room_key, card_key, ack_key, all_key]:
		context.erase(temporary_key)
	return game.queue_resolution({"type": "chaos_resolution", "context": context.duplicate(false),
		"card": revealed, "mode": mode, "room_id": room_id})


func process_chaos_resolution(resolution: Dictionary) -> bool:
	var context: Dictionary = resolution.context
	var game = _game(context)
	var caster_id: int = _caster(context)
	if not bool(resolution.get("started", false)):
		resolution["started"] = true
		var room_id: String = str(resolution.room_id)
		match str(resolution.mode):
			"damage":
				var damage_context := context.duplicate(false)
				damage_context["target_room_id"] = room_id
				damage_context["spell_target_type"] = "room"
				_resolve_damage({"type": "damage", "amount": 2, "target": "room"}, damage_context)
			"instability":
				game.place_instability(caster_id, room_id, 1)
			"activate_room":
				game.activate_room(caster_id, room_id, true, {"source_kind": "chaos",
					"caster_id": caster_id, "caster_room_id": game.players[caster_id].mage.room_id,
					"force_room_activation": true})
		return false

	# Array.back() is the top of the Grimoire. Returning at index zero also
	# preserves the order of all other cards, including identical printed copies.
	var card: SpellCardState = resolution.card
	game.players[caster_id].grimoire.push_front(card)
	print("Chaos: ", card.card_name, " returned to the bottom of Player ", caster_id + 1, "'s Grimoire")
	return true
