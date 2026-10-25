extends GutTest
## The game scene on its own: a local match against three bots, the HUD and pause.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func test_the_player_holds_slot_one_against_three_bots():
	assert_eq(game.my_slot, 0)
	assert_eq(game.mode, "local")
	assert_eq(game.get_node("HUD/Scores/Slot0Label").text, "P1 (you): 0")
	assert_eq(game.get_node("HUD/Scores/Slot1Label").text, "P2 (bot): 0")


func test_the_round_starts_after_the_warmup():
	assert_eq(game.state, "warmup")
	await wait_physics_frames(ArenaMatch.WARMUP_TICKS + 4)
	assert_eq(game.state, "round")
	assert_eq(game.get_node("HUD/RoundLabel").text, "Round 1")
	assert_eq(game.get_node("HUD/HealthLabel").text, "Health: 5")


func test_pause_stops_the_local_match():
	await wait_physics_frames(ArenaMatch.WARMUP_TICKS + 4)
	game.get_node("HUD/PauseButton").pressed.emit()
	assert_true(get_tree().paused)
	assert_true(game.get_node("PauseMenu").visible)
	game.get_node("PauseMenu/ResumeButton").pressed.emit()
	assert_false(get_tree().paused)
