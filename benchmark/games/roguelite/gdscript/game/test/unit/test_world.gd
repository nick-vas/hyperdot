extends GutTest
## World over time: the wick's pace, enemies hunting it round corners, embers, a swarm, and a floor that plays the same
## twice from one seed.

var floors := Floors.from_files()


func _world(rows: Array, hp := 5) -> World:
	return World.create(Dungeon.from_text(PackedStringArray(rows)), floors.kinds, 1, hp, hp)


func test_the_wick_steps_once_every_few_ticks():
	var world := _world(["############", "#S.........#", "############"])
	for i in World.WICK_MOVE_TICKS * 3:
		world.step(Vector2i.RIGHT, false)
	assert_eq(world.wick.cell, Vector2i(4, 1))
	assert_eq(world.wick.facing, Vector2i.RIGHT)


func test_an_enemy_that_sees_the_wick_hunts_it_round_a_corner():
	var world := _world([
		"#########",
		"#S......#",
		"#.#######",
		"#b......#",
		"#########",
	], 20)
	var bat := world.enemies[0]
	world.step(Vector2i.ZERO, false)
	assert_gt(bat.alert, 0, "it saw the wick")
	for i in World.WICK_MOVE_TICKS * 6:
		world.step(Vector2i.RIGHT, false)
	assert_eq(world.wick.cell, Vector2i(7, 1))
	for i in 200:
		world.step(Vector2i.ZERO, false)
	assert_true(World.adjacent(bat.cell, world.wick.cell), "it followed the wick round the corner")


func test_snuffed_enemies_leave_their_embers():
	# Kinds of its own, so the count does not move with the data.
	var kinds := {
		"brute": {"id": "brute", "hp": 1, "damage": 1, "embers": 3},
		"shade": {"id": "shade", "hp": 1, "damage": 1, "embers": 1},
	}
	var rows := PackedStringArray(["#####", "##B##", "#BSs#", "##B##", "#####"])
	var world := World.create(Dungeon.from_text(rows), kinds, 1, 20, 20)
	for i in World.WICK_ATTACK_TICKS * 4:
		world.step(Vector2i.ZERO, true)
	assert_eq(world.enemies.size(), 0)
	assert_eq(world.embers, 10)


func test_a_swarm_hunts_from_afar():
	var world := World.create(Dungeon.generate(7, floors.spec(1)), floors.kinds, 7, 5, 5)
	var before := world.enemies.size()
	world.add_swarm(50, floors.kind("bat"))
	assert_eq(world.enemies.size(), before + 50)
	var field := world.dungeon.distance_field(world.wick.cell)
	for i in range(before, world.enemies.size()):
		var bat := world.enemies[i]
		assert_gte(field[world.dungeon.index(bat.cell)], 6, "far from the wick")
		assert_gt(bat.alert, 0, "already hunting")


func test_a_floor_plays_the_same_twice_from_one_seed():
	var runs: Array[String] = []
	for attempt in 2:
		var world := World.create(Dungeon.generate(5 * 1009 + 1, floors.spec(1)), floors.kinds, 5 * 1009 + 1, 5, 5)
		var bot := Bot.new()
		for i in 900:
			var choice := bot.choose(world)
			world.step(choice.move, choice.attack)
		var cells := PackedStringArray()
		for enemy in world.enemies:
			cells.append(str(enemy.cell))
		runs.append("%s %d %d %s" % [world.wick.cell, world.wick.hp, world.embers, ",".join(cells)])
	assert_eq(runs[1], runs[0])
