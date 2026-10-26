extends GutTest
## Hidden check for the alpha's fix-architecture: the HUD's round label still follows the round, kept up to date by
## the game rather than looked up every frame.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(ArenaMatch.WARMUP_TICKS + 4)


func test_hidden_the_label_shows_the_first_round():
	assert_eq(game.state, "round")
	assert_eq(game.get_node("HUD/RoundLabel").text, "Round 1")


func test_hidden_the_label_follows_the_next_round():
	for slot in [1, 2, 3]:
		for i in ArenaMatch.HP:
			game.server.arena._damage(0, slot)
	await wait_physics_frames(ArenaMatch.INTERMISSION_TICKS + 6)
	assert_eq(game.round_number, 2)
	assert_eq(game.get_node("HUD/RoundLabel").text, "Round 2")


func test_hidden_the_label_follows_a_new_match():
	for slot in [1, 2, 3]:
		for i in ArenaMatch.HP:
			game.server.arena._damage(0, slot)
	await wait_physics_frames(ArenaMatch.INTERMISSION_TICKS + 6)
	game.start_match(7)
	await wait_physics_frames(3)
	assert_eq(game.get_node("HUD/RoundLabel").text, "Round 0")
	await wait_physics_frames(ArenaMatch.WARMUP_TICKS + 4)
	assert_eq(game.get_node("HUD/RoundLabel").text, "Round 1")
