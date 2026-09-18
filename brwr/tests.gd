extends RefCounted


static func run(game) -> void:

	print("")
	print("========================================")
	print("SPECIAL ROOM TESTS")
	print("SUMMONER / MIRRORS / THRONE")
	print("========================================")

	var passed: int = 0
	var total: int = 0


	# =====================================================
	# RESET ROOM ACTIVATIONS
	# =====================================================

	game.reset_room_activations()


	# =====================================================
	# TEST 1
	# SUMMONER ROOM
	#
	# Rebuilt:
	# Summon Nigredo at range 0
	# then immediately activate it.
	#
	# Qui verifichiamo soprattutto che il Nigredo
	# venga effettivamente creato.
	# =====================================================

	print("")
	print("--- TEST: Summoner Room rebuilt ---")

	var summoner = game.get_room_by_id(
		"summoner_room"
	)

	if summoner == null:

		print("FAIL: Summoner Room not found")

	else:

		summoner.flipped = true
		summoner.reset_activation()


		var player = game.players[0]
		var mage = player.mage


		mage.in_cell = false


		var nigredo_before: int = 0

		for evocation in player.evocations:

			if evocation.evocation_id == "nigredo":
				nigredo_before += 1


		var summoner_context: Dictionary = {
			"target_room_id": mage.room_id
		}


		var summoner_result: bool = game.activate_room(
			0,
			"summoner_room",
			false,
			summoner_context
		)


		total += 1

		if summoner_result:

			print(
				"PASS: Summoner Room activated"
			)

			passed += 1

		else:

			print(
				"FAIL: Summoner Room activation failed"
			)


		var nigredo_after: int = 0

		for evocation in player.evocations:

			if evocation.evocation_id == "nigredo":
				nigredo_after += 1


		total += 1

		if nigredo_after == nigredo_before + 1:

			print(
				"PASS: Nigredo summoned"
			)

			passed += 1

		else:

			print(
				"FAIL: expected ",
				nigredo_before + 1,
				" Nigredo, found ",
				nigredo_after
			)


	# =====================================================
	# TEST 2
	# MIRRORS ROOM
	#
	# Copiamo Observatory:
	# "All other Mages lose 1 Power"
	#
	# È una buona Room da copiare perché non richiede
	# target o altri context.
	# =====================================================

	print("")
	print("--- TEST: Mirrors Room rebuilt ---")

	var mirrors = game.get_room_by_id(
		"mirrors_room"
	)

	if mirrors == null:

		print("FAIL: Mirrors Room not found")

	elif game.players.size() < 2:

		print(
			"FAIL: Mirrors test requires at least 2 players"
		)

	else:

		mirrors.flipped = true
		mirrors.reset_activation()


		for i in range(
			game.players.size()
		):

			game.players[i].power = 5


		var mirrors_context: Dictionary = {
			"copied_room_id": "observatory"
		}


		var mirrors_result: bool = game.activate_room(
			0,
			"mirrors_room",
			false,
			mirrors_context
		)


		total += 1

		if mirrors_result:

			print(
				"PASS: Mirrors Room activated"
			)

			passed += 1

		else:

			print(
				"FAIL: Mirrors Room activation failed"
			)


		total += 1

		if game.players[0].power == 5:

			print(
				"PASS: activating player kept Power"
			)

			passed += 1

		else:

			print(
				"FAIL: activating player Power = ",
				game.players[0].power,
				", expected 5"
			)


		var other_players_ok: bool = true

		for i in range(
			1,
			game.players.size()
		):

			if game.players[i].power != 4:

				other_players_ok = false

				print(
					"FAIL: Player ",
					i + 1,
					" Power = ",
					game.players[i].power,
					", expected 4"
				)


		total += 1

		if other_players_ok:

			print(
				"PASS: copied Observatory effect resolved"
			)

			passed += 1


		# ---------------------------------------------
		# Mirrors must NOT activate the copied Room.
		# ---------------------------------------------

		var observatory = game.get_room_by_id(
			"observatory"
		)

		total += 1

		if (
			observatory != null
			and not observatory.activated_this_turn
		):

			print(
				"PASS: copied Room was not marked activated"
			)

			passed += 1

		else:

			print(
				"FAIL: Observatory was marked activated"
			)


	# =====================================================
	# TEST 3
	# MIRRORS INVALID TARGETS
	#
	# Black Rose and Throne cannot be copied.
	# =====================================================

	print("")
	print("--- TEST: Mirrors exclusions ---")


	if mirrors != null:

		mirrors.reset_activation()


		var black_rose_result: bool = game.activate_room(
			0,
			"mirrors_room",
			false,
			{
				"copied_room_id": "black_rose"
			}
		)


		total += 1

		if not black_rose_result:

			print(
				"PASS: Black Rose cannot be copied"
			)

			passed += 1

		else:

			print(
				"FAIL: Mirrors copied Black Rose"
			)


		mirrors.reset_activation()


		var throne_copy_result: bool = game.activate_room(
			0,
			"mirrors_room",
			false,
			{
				"copied_room_id": "throne"
			}
		)


		total += 1

		if not throne_copy_result:

			print(
				"PASS: Throne cannot be copied"
			)

			passed += 1

		else:

			print(
				"FAIL: Mirrors copied Throne"
			)


	# =====================================================
	# TEST 4
	# THRONE ROOM REBUILT
	#
	# Take Crown
	# Gain 1 Power
	# =====================================================

	print("")
	print("--- TEST: Throne Room rebuilt ---")

	var throne = game.get_room_by_id(
		"throne"
	)

	if throne == null:

		print("FAIL: Throne Room not found")

	else:

		throne.flipped = true
		throne.reset_activation()


		game.crown_owner_id = -1

		game.players[0].power = 5


		var throne_result: bool = game.activate_room(
			0,
			"throne"
		)


		total += 1

		if throne_result:

			print(
				"PASS: Throne rebuilt activated"
			)

			passed += 1

		else:

			print(
				"FAIL: Throne rebuilt activation failed"
			)


		total += 1

		if game.crown_owner_id == 0:

			print(
				"PASS: Player 1 took Crown"
			)

			passed += 1

		else:

			print(
				"FAIL: Crown owner = ",
				game.crown_owner_id,
				", expected 0"
			)


		total += 1

		if game.players[0].power == 6:

			print(
				"PASS: Player 1 gained 1 Power"
			)

			passed += 1

		else:

			print(
				"FAIL: Player 1 Power = ",
				game.players[0].power,
				", expected 6"
			)


	# =====================================================
	# TEST 5
	# THRONE DESTROYED
	#
	# Lose 1 Power -> take Crown
	# =====================================================

	print("")
	print("--- TEST: Throne Room destroyed ---")


	if throne != null:

		throne.flipped = false
		throne.reset_activation()


		game.crown_owner_id = 1

		game.players[0].power = 3


		var destroyed_result: bool = game.activate_room(
			0,
			"throne"
		)


		total += 1

		if destroyed_result:

			print(
				"PASS: Throne destroyed activated"
			)

			passed += 1

		else:

			print(
				"FAIL: Throne destroyed activation failed"
			)


		total += 1

		if game.players[0].power == 2:

			print(
				"PASS: Player 1 paid 1 Power"
			)

			passed += 1

		else:

			print(
				"FAIL: Player 1 Power = ",
				game.players[0].power,
				", expected 2"
			)


		total += 1

		if game.crown_owner_id == 0:

			print(
				"PASS: Player 1 took Crown after payment"
			)

			passed += 1

		else:

			print(
				"FAIL: Crown owner = ",
				game.crown_owner_id,
				", expected 0"
			)


	# =====================================================
	# FINAL RESULT
	# =====================================================

	print("")
	print("========================================")
	print(
		"SPECIAL ROOM TEST RESULT: ",
		passed,
		"/",
		total
	)
	print("========================================")
	print("")
