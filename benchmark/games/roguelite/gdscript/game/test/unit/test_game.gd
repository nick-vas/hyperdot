extends GutTest
## The game scene: a floor drawn and played from the input, the HUD, the next floor, and the panel at the end of a run.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_run(7)
	await wait_physics_frames(2)


func test_a_run_starts_on_floor_1():
	assert_eq(game.floor_number, 1)
	assert_eq(game.state, "playing")
	assert_eq(game.wick_cell, game.world.dungeon.start)
	assert_eq(game.get_node("HUD/FloorLabel").text, "Floor 1: The Wax Cellar")
	assert_eq(game.get_node("HUD/HpLabel").text, "Wick: 5 / 5")


func test_the_wick_walks_where_the_player_holds():
	var start: Vector2i = game.wick_cell
	var dir := Vector2i.ZERO
	for candidate: Vector2i in Dungeon.DIRS:
		if game.world.dungeon.is_floor(start + candidate):
			dir = candidate
			break
	var action: String = {Vector2i.UP: "move_up", Vector2i.RIGHT: "move_right", Vector2i.DOWN: "move_down", Vector2i.LEFT: "move_left"}[dir]
	Input.action_press(action)
	await wait_physics_frames(3)
	Input.action_release(action)
	assert_eq(game.wick_cell, start + dir)


func test_a_hurt_shows_on_the_hud():
	game.world.hurt_wick(2)
	assert_eq(game.get_node("HUD/HpLabel").text, "Wick: 3 / 5")


func test_the_open_stairs_lead_to_floor_2():
	for enemy in game.world.enemies.duplicate():
		enemy.hp = 1
		game.world.wick.attack_cooldown = 0
		game.world.wick.facing = Vector2i.ZERO
		game.world._occupied.erase(enemy.cell)
		enemy.cell = game.world.wick.cell + Vector2i.UP
		game.world._occupied[enemy.cell] = enemy
		game.world.step(Vector2i.ZERO, true)
	assert_true(game.world.stairs_open)
	assert_eq(game.get_node("HUD/EnemiesLabel").text, "The stairs are open")
	game.world.wick.cell = game.world.dungeon.stairs
	await wait_physics_frames(game.NEXT_FLOOR_TICKS + 5)
	assert_eq(game.floor_number, 2)
	assert_eq(game.get_node("HUD/FloorLabel").text, "Floor 2: The Ossuary")


func test_a_snuffed_wick_ends_the_run_with_the_panel():
	game.world.wick.hp = 1
	game.world.hurt_wick(1)
	await wait_physics_frames(2)
	assert_eq(game.state, "over")
	assert_true(game.get_node("RunOverMenu").visible)
	assert_eq(game.get_node("RunOverMenu/Box/Title").text, "The wick is out")
	game.get_node("RunOverMenu/Box/AgainButton").pressed.emit()
	assert_eq(game.state, "playing")
	assert_eq(game.floor_number, 1)
