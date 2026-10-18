class_name AvatarState
extends RefCounted

# Only Avatar-specific state lives here. Location, damage, summons and Quests
# remain on the existing PlayerState/MageState; Power and cubes belong to BR.
var game: Node
var player_index := -1
var definition: Dictionary = {}
var difficulty := "apprentice"
var commands_used := 0
var decks: Dictionary = {1: [], 2: [], 3: []}
var active_command: SpellCardState
var network_public: Dictionary = {}

func command_limit() -> int:
	return 4 if difficulty == "master" else 3

func active_deck() -> Array[SpellCardState]:
	return decks.get(game.current_moon, [])

func can_activate() -> bool:
	return commands_used < command_limit() and not active_deck().is_empty()

func draw_command(additional: bool = false) -> SpellCardState:
	if (not additional and not can_activate()) or active_deck().is_empty():
		return null
	var card: SpellCardState = active_deck().pop_back()
	if not additional:
		commands_used += 1
	game.players[player_index].memories.append(card)
	active_command = card
	return card

func recycle_memories() -> void:
	var player: PlayerState = game.players[player_index]
	for moon in [1, 2, 3]:
		var returned: Array[SpellCardState] = []
		for card in player.memories:
			if int(card.avatar_command.get("moon", 0)) == moon:
				returned.append(card)
		game.shuffle_with_rng(returned)
		# The top is the end, like the other game decks. Keep undrawn cards on top.
		returned.append_array(decks[moon])
		decks[moon] = returned
	player.memories.clear()
	player.revealed_spells.clear()
	active_command = null

func public_data() -> Dictionary:
	if game.network_client and not network_public.is_empty(): return network_public
	var counts: Dictionary = {}
	for moon in decks:
		counts[moon] = decks[moon].size()
	var top: SpellCardState = active_deck().back() if not active_deck().is_empty() else null
	return {"id": definition.get("id", ""), "player_index": player_index,
		"difficulty": difficulty, "commands_used": commands_used, "command_limit": command_limit(),
		"deck_counts": counts, "active_command": active_command.id if active_command != null else "",
		"reaction": top.avatar_command.get("reaction", {}).get("trigger", "") if top != null else "",
		"memories": game.players[player_index].memories.map(func(card): return card.id)}
