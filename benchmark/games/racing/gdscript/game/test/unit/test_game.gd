extends GutTest
## The race scene: the countdown, the player's car on the keys, the HUD, the ghost after a lap, and pause.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func after_each():
	Input.action_release("accelerate")
	Input.action_release("steer_right")


func _seconds(s: float) -> int:
	return roundi(s * Engine.physics_ticks_per_second)


func test_the_race_waits_for_the_countdown():
	assert_eq(game.state, "countdown")
	var start: Vector2 = game.race.cars[1].position
	await wait_physics_frames(_seconds(1.0))
	assert_eq(game.race.cars[1].position, start, "nobody moves before the start")
	await wait_physics_frames(_seconds(2.5))
	assert_eq(game.state, "racing")
	assert_ne(game.race.cars[1].position, start)


func test_the_accelerate_key_drives_the_players_car():
	await wait_physics_frames(_seconds(3.0) + 1)
	Input.action_press("accelerate")
	await wait_physics_frames(_seconds(1.0))
	assert_gt(game.race.cars[0].speed, 200.0)


func test_the_hud_shows_the_lap_and_the_place():
	assert_eq(game.get_node("HUD/LapLabel").text, "Lap 1/3")
	assert_eq(game.get_node("HUD/PositionLabel").text, "P4/4")
	assert_eq(game.get_node("HUD/TrackLabel").text, "Ashfall Oval")


func test_after_a_lap_the_ghost_drives_it_again():
	game.race.drivers[0] = AiDriver.new()
	game.state = "racing"
	while game.race.trackers[0].laps < 1:
		await wait_physics_frames(10)
	assert_eq(game.lap, 2)
	assert_true(game.get_node("Ghost").visible)
	assert_eq(game.get_node("HUD/LapLabel").text, "Lap 2/3")


func test_the_pause_menu_stops_the_race():
	game.get_node("HUD/PauseButton").pressed.emit()
	assert_true(get_tree().paused)
	game.get_node("PauseMenu/ResumeButton").pressed.emit()
	assert_false(get_tree().paused)
