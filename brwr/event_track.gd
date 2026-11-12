class_name EventTrack
extends RefCounted

# Three slots, each ordered from the bottom card to the most recently placed.
static func cards_in(slots: Array, index: int) -> Array:
	var slot = slots[index]
	if slot is Array:
		return slot
	# Older game states and recordings stored one Event (or null) per slot.
	return [slot] if slot is EventCardState else []

static func all_cards(slots: Array) -> Array:
	var cards := []
	for i in slots.size():
		cards.append_array(cards_in(slots, i))
	return cards

static func choices(slots: Array) -> Array:
	var options := []
	for i in slots.size():
		for event: EventCardState in cards_in(slots, i):
			options.append({"token": "event:" + event.id, "value": event, "slot_index": i,
				"id": event.id, "name": event.event_name, "card_kind": "events"})
	return options

static func discard_from_slot(game, event: EventCardState, gain_power: bool) -> bool:
	if event == null:
		return false
	for i in game.active_events.size():
		var cards := cards_in(game.active_events, i)
		if cards.has(event):
			cards.erase(event)
			game.active_events[i] = cards
			game.discard_event(event, gain_power)
			return true
	return false

static func refill_deck(game, moon: int) -> void:
	var deck: Array = game.event_decks[moon]
	if not deck.is_empty():
		return
	for i in range(game.event_discard.size() - 1, -1, -1):
		if game.event_discard[i].moon == moon:
			deck.append(game.event_discard.pop_at(i))
	game.shuffle_with_rng(deck)
