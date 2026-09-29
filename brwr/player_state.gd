class_name PlayerState
extends RefCounted


const MAX_CUBES: int = 25

const MAX_PHYSICAL_ACTIONS: int = 2

var available_physical_actions: int = MAX_PHYSICAL_ACTIONS
var player_index: int
var player_name: String
var color: Color

var evocations: Array[EvocationState] = []

var power: int = 0
var hand_limit: int = 6
var available_cubes: int = MAX_CUBES
var max_active_quests: int = 2
var active_quests: Array[QuestState] = []
var completed_quests: Array[QuestState] = []
var personal_spell_id: String = ""
var active_spells: Array[ActiveSpellState] = []
var personal_spell_copies_received: int = 0
var mage_id: String = ""
var school_id: String = ""
var starting_grimoire_id: String = ""
var starting_grimoire_name: String = ""

var mage: MageState

var revealed_spells: Array[RevealedSpellState] = []
# =========================================================
# READY SPELLS
# =========================================================

# Slot I, II, III.
#
# L'ordine dell'Array corrisponde all'ordine di lancio:
# index 0 = I
# index 1 = II
# index 2 = III
var ready_spells: Array[ReadySpellState] = []
var quick_spell: ReadySpellState = null

# =========================================================
# SPELL CARDS
# =========================================================

# Carte attualmente in mano.
var hand: Array[SpellCardState] = []

# Mazzo personale del giocatore.
var grimoire: Array[SpellCardState] = []

# Pila degli scarti personale.
var memories: Array[SpellCardState] = []
# =========================================================
# READY SPELLS
# =========================================================

# Ready Spells negli slot I, II e III.
# L'ordine dell'Array corrisponde all'ordine di lancio.


func _init(
	index: int,
	name: String,
	player_color: Color
):
	player_index = index
	player_name = name
	color = player_color

	# Temporaneo: tutti i Mage hanno 10 Health.
	# Quando creeremo il database dei Mage, questo valore
	# verrà letto dai dati del Mage scelto.
	mage = MageState.new(
		"",
		10
	)


# =========================================================
# CUBES
# =========================================================

func take_cubes(
	amount: int
) -> int:

	var taken = min(
		max(amount, 0),
		available_cubes
	)

	available_cubes -= taken

	return taken


func return_cubes(
	amount: int
):
	available_cubes = min(
		available_cubes + max(amount, 0),
		MAX_CUBES
	)


# =========================================================
# EVOCATIONS
# =========================================================

func has_free_evocation_slot() -> bool:
	return evocations.size() < 3


func add_evocation(
	evocation: EvocationState
) -> bool:

	if not has_free_evocation_slot():
		return false

	# Keep a physical number for this instance; removing another does not renumber it.
	var used_numbers: Array[int] = []
	for existing in evocations:
		used_numbers.append(existing.board_number)
	for number in range(1, 4):
		if not used_numbers.has(number):
			evocation.board_number = number
			break

	evocations.append(
		evocation
	)

	return true


# =========================================================
# ACTIVE SPELLS
# =========================================================

func add_active_spell(
	active_spell: ActiveSpellState
):
	active_spells.append(
		active_spell
	)


func remove_active_spell(
	active_spell: ActiveSpellState
):
	var index = active_spells.find(
		active_spell
	)

	if index != -1:
		active_spells.remove_at(
			index
		)


# =========================================================
# REVEALED SPELLS
# =========================================================

func add_revealed_spell(
	revealed_spell: RevealedSpellState
):
	revealed_spells.append(
		revealed_spell
	)


# =========================================================
# HAND
# =========================================================

func get_hand_limit() -> int:
	return hand_limit
	
func add_spell_to_hand(
	spell: SpellCardState
):
	if spell == null:
		return

	hand.append(
		spell
	)


func remove_spell_from_hand(
	spell: SpellCardState
) -> bool:

	var index = hand.find(
		spell
	)

	if index == -1:
		return false

	hand.remove_at(
		index
	)

	return true


func get_spell_from_hand(
	spell_id: String
) -> SpellCardState:

	for spell in hand:

		if spell.id == spell_id:
			return spell

	return null


# =========================================================
# GRIMOIRE
# =========================================================

func add_spell_to_grimoire(
	spell: SpellCardState
):
	if spell == null:
		return

	grimoire.append(
		spell
	)


func draw_from_grimoire() -> SpellCardState:

	if grimoire.is_empty():
		return null

	var spell: SpellCardState = (
		grimoire.pop_back()
	)

	hand.append(
		spell
	)

	return spell


# =========================================================
# MEMORIES
# =========================================================

func add_spell_to_memories(
	spell: SpellCardState
):
	if spell == null:
		return

	memories.append(
		spell
	)


func discard_spell_from_hand(
	spell: SpellCardState
) -> bool:

	if not remove_spell_from_hand(
		spell
	):
		return false

	memories.append(
		spell
	)

	return true


func get_spell_from_memories(
	spell_id: String
) -> SpellCardState:

	for spell in memories:

		if spell.id == spell_id:
			return spell

	return null


# =========================================================
# CARD COUNTS
# =========================================================

func get_hand_size() -> int:
	return hand.size()


func get_grimoire_size() -> int:
	return grimoire.size()


func get_memories_size() -> int:
	return memories.size()

func add_ready_spell(
	spell: SpellCardState,
	use_dark_side: bool = false
) -> bool:

	if spell == null:
		return false

	if ready_spells.size() >= 3:
		return false

	var hand_index = hand.find(
		spell
	)

	if hand_index == -1:
		return false

	hand.remove_at(
		hand_index
	)

	ready_spells.append(
		ReadySpellState.new(
			spell,
			use_dark_side
		)
	)

	return true


func set_quick_spell(
	spell: SpellCardState,
	use_dark_side: bool = false
) -> bool:

	if spell == null:
		return false

	if quick_spell != null:
		return false

	var hand_index = hand.find(
		spell
	)

	if hand_index == -1:
		return false

	hand.remove_at(
		hand_index
	)

	quick_spell = ReadySpellState.new(
		spell,
		use_dark_side
	)

	return true


func get_next_ready_spell() -> ReadySpellState:

	if ready_spells.is_empty():
		return null

	return ready_spells[0]


func remove_next_ready_spell() -> ReadySpellState:

	if ready_spells.is_empty():
		return null

	return ready_spells.pop_front()
# =========================================================
# PHYSICAL ACTIONS
# =========================================================

func has_physical_action() -> bool:
	return available_physical_actions > 0


func exhaust_physical_action() -> bool:

	if available_physical_actions <= 0:
		return false

	available_physical_actions -= 1

	return true


func refresh_physical_actions():
	available_physical_actions = MAX_PHYSICAL_ACTIONS
