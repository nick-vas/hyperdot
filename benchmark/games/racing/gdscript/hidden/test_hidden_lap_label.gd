extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's lap counter follows the player's laps, a restart and a new
## track, as it did before.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func _label() -> String:
	return game.get_node("HUD/LapLabel").text


func test_hidden_the_lap_counter_starts_at_lap_1():
	assert_eq(_label(), "Lap 1/3")


func test_hidden_the_lap_counter_follows_a_lap():
	game.race.drivers[0] = AiDriver.new()
	game.state = "racing"
	while game.race.trackers[0].laps < 1:
		await wait_physics_frames(5)
	await wait_physics_frames(1)
	assert_eq(_label(), "Lap 2/3")


func test_hidden_a_restart_and_a_new_track_reset_it():
	game.race.drivers[0] = AiDriver.new()
	game.state = "racing"
	while game.race.trackers[0].laps < 1:
		await wait_physics_frames(5)
	game.restart()
	await wait_physics_frames(1)
	assert_eq(_label(), "Lap 1/3")
	game.start_track(2)
	await wait_physics_frames(1)
	assert_eq(_label(), "Lap 1/2")


func test_hidden_the_counter_is_right_without_the_cars_drawn():
	for view in game.get_node("Cars").get_children():
		view.process_mode = Node.PROCESS_MODE_DISABLED
	game.race.drivers[0] = AiDriver.new()
	game.state = "racing"
	while game.race.trackers[0].laps < 1:
		await wait_physics_frames(5)
	await wait_physics_frames(1)
	assert_eq(_label(), "Lap 2/3")
