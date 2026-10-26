extends GutTest
## World's rules on small floors drawn by hand: walls and creatures block a step, an enemy sees only so far and never
## through a wall, strikes only from beside the wick, the wick's blow wounds and snuffs, and the stairs wait for the last
## enemy.

var floors := Floors.from_files()


func _world(rows: Array, hp := 5) -> World:
	return World.create(Dungeon.from_text(PackedStringArray(rows)), floors.kinds, 1, hp, hp)


func _steps(world: World, ticks: int, move := Vector2i.ZERO, attack := false) -> void:
	for i in ticks:
		world.step(move, attack)


func test_a_wall_stops_the_wick():
	var world := _world(["#####", "#S..#", "#####"])
	_steps(world, 20, Vector2i.UP)
	assert_eq(world.wick.cell, Vector2i(1, 1))
	_steps(world, 20, Vector2i.LEFT)
	assert_eq(world.wick.cell, Vector2i(1, 1))


func test_the_wick_cannot_step_onto_an_enemy():
	var world := _world(["#######", "#S.s.>#", "#######"])
	_steps(world, 40, Vector2i.RIGHT)
	assert_eq(world.wick.cell, Vector2i(2, 1))
	assert_eq(world.enemies[0].cell, Vector2i(3, 1))


func test_an_enemy_does_not_see_through_a_wall():
	var world := _world([
		"#########",
		"#S..#..s#",
		"#.......#",
		"#.......#",
		"#########",
	])
	var shade := world.enemies[0]
	assert_false(world.sees(shade), "the wall is between them")
	shade.cell = Vector2i(6, 2)
	assert_true(world.sees(shade), "a clear line")


func test_an_enemy_sees_no_further_than_its_sight():
	var world := _world(["##########", "#S.......#", "##########"])
	var shade := Actor.from_kind(floors.kind("shade"), Vector2i(8, 1))
	world.add_enemy(shade)
	assert_eq(shade.sight, 6)
	assert_false(world.sees(shade), "seven cells away")
	shade.cell = Vector2i(7, 1)
	assert_true(world.sees(shade), "six cells away")


func test_an_enemy_strikes_from_beside_the_wick_not_from_a_diagonal():
	assert_true(World.adjacent(Vector2i(2, 2), Vector2i(3, 2)))
	assert_true(World.adjacent(Vector2i(2, 2), Vector2i(2, 1)))
	assert_false(World.adjacent(Vector2i(2, 2), Vector2i(3, 3)))
	assert_false(World.adjacent(Vector2i(2, 2), Vector2i(4, 2)))
	var world := _world(["#####", "#Ss.#", "#####"])
	_steps(world, World.WINDUP_TICKS + 5)
	assert_eq(world.wick.hp, 5 - int(floors.kind("shade").damage))


func test_the_blow_wounds_the_enemy_the_wick_faces():
	var world := _world(["######", "#.Ss.#", "#.s..#", "######"])
	var facing := world.enemies[0]
	world.step(Vector2i.RIGHT, false)
	assert_eq(world.wick.cell, Vector2i(2, 1), "the shade is in the way")
	world.step(Vector2i.ZERO, true)
	assert_eq(facing.hp, int(floors.kind("shade").hp) - 1, "it faces this shade")
	assert_eq(world.enemies[1].hp, int(floors.kind("shade").hp), "the shade below is spared")


func test_an_enemy_at_no_hp_is_snuffed():
	var world := _world(["######", "#Ss..#", "#..s.#", "#...>#", "######"])
	var shade := world.enemies[0]
	shade.hp = 1
	world.step(Vector2i.ZERO, true)
	assert_eq(world.enemies.size(), 1)
	assert_false(world.enemies.has(shade))
	assert_eq(world.embers, int(floors.kind("shade").embers))
	assert_null(world.enemy_at(Vector2i(2, 1)), "its cell is free")


func test_the_stairs_open_only_when_every_enemy_is_gone():
	var world := _world([
		"#######",
		"#.bS>.#",
		"#.....#",
		"#b....#",
		"#######",
	], 20)
	assert_false(world.stairs_open)
	world.step(Vector2i.ZERO, true)
	assert_eq(world.enemies.size(), 1, "the bat beside the wick is snuffed")
	assert_false(world.stairs_open, "one bat left")
	_steps(world, 5, Vector2i.RIGHT)
	assert_eq(world.wick.cell, Vector2i(4, 1), "on the stairs")
	assert_false(world.done, "the stairs are shut")
	world.enemies[0].hp = 1
	for i in 300:
		world.step(Vector2i.ZERO, true)
		if world.enemies.is_empty():
			break
	assert_true(world.stairs_open)
	world.step(Vector2i.ZERO, false)
	assert_true(world.done, "the wick stands on the open stairs")
