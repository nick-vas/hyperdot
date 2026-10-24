extends GutTest
## Hidden check for the beta's fix-performance: a swarm hunting the wick costs one search of the floor per cell the wick
## moves, not one per hunter's step; and the hunters still close in, round corners.

var floors := Floors.from_files()


func _swarmed() -> World:
	var world := World.create(Dungeon.generate(7, floors.spec(1)), floors.kinds, 7, 99, 99)
	world.add_swarm(150, floors.kind("bat"))
	return world


func test_hidden_a_still_wick_costs_one_search():
	var world := _swarmed()
	var field := world.dungeon.distance_field(world.wick.cell)
	var start := {}
	for enemy in world.enemies:
		start[enemy] = field[world.dungeon.index(enemy.cell)]
	for i in 240:
		world.step(Vector2i.ZERO, false)
	assert_lte(world.path_searches, 2)
	# The corridors jam a swarm, so not every hunter gains ground; many must.
	var closer := 0
	var near := 0
	for enemy in world.enemies:
		var distance := field[world.dungeon.index(enemy.cell)]
		if distance < int(start[enemy]):
			closer += 1
		if distance <= 4:
			near += 1
	assert_gte(closer, 40, "%d hunters gained ground" % closer)
	assert_gte(near, 4, "%d hunters within four steps" % near)


func test_hidden_a_moving_wick_costs_a_search_per_cell():
	var world := _swarmed()
	var moves := 0
	var last := world.wick.cell
	for i in 240:
		var dir: Vector2i = Dungeon.DIRS[(i / 30) % 4]
		world.step(dir, false)
		if world.wick.cell != last:
			moves += 1
			last = world.wick.cell
	assert_lte(world.path_searches, moves + 2, "%d searches for %d moves" % [world.path_searches, moves])


func test_hidden_a_hunter_still_finds_the_way_round():
	var world := World.create(Dungeon.from_text(PackedStringArray([
		"#########",
		"#S......#",
		"#.#######",
		"#b......#",
		"#########",
	])), floors.kinds, 1, 20, 20)
	for i in World.WICK_MOVE_TICKS * 6:
		world.step(Vector2i.RIGHT, false)
	for i in 200:
		world.step(Vector2i.ZERO, false)
	assert_true(World.adjacent(world.enemies[0].cell, world.wick.cell))
