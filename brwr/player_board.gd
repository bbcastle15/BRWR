extends Control

var player_state: PlayerState


func setup(player: PlayerState):
	player_state = player
	refresh()


func refresh():
	if player_state == null:
		return

	$PlayerName.text = player_state.player_name

	if player_state.mage.mage_id == "":
		$MageName.text = "Mage: -"
	else:
		$MageName.text = "Mage: " + player_state.mage.mage_id

	$HealthLabel.text = (
		"HP: "
		+ str(player_state.mage.get_remaining_health())
		+ "/"
		+ str(player_state.mage.health)
	)

	$PowerLabel.text = "Power: " + str(player_state.power)
	$CubeLabel.text = "Cubes: " + str(player_state.available_cubes)

	$HandInfo.text = "Hand: 0"
