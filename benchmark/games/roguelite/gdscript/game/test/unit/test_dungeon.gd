extends GutTest
## Dungeon: the generator's hard rules over a sweep of seeds, its seed, and the searches the enemies and the bot use.

var floors := Floors.from_files()


func test_every_floor_cell_is_reachable_from_the_start():
	for number in range(1, floors.count() + 1):
		for seed_value in range(1, 61):
			var dungeon := Dungeon.generate(seed_value * 1009 + number, floors.spec(number))
			assert_eq(dungeon.unreachable_cells(), 0, "floor %d, seed %d" % [number, seed_value])


func test_rooms_keep_a_wall_between_them_and_round_the_edge():
	for seed_value in range(1, 41):
		var dungeon := Dungeon.generate(seed_value, floors.spec(1))
		var whole := Rect2i(1, 1, dungeon.width - 2, dungeon.height - 2)
		for i in dungeon.rooms.size():
			assert_true(whole.encloses(dungeon.rooms[i]), "seed %d room %d inside the edge" % [seed_value, i])
			for j in range(i + 1, dungeon.rooms.size()):
				assert_false(dungeon.rooms[i].grow(1).intersects(dungeon.rooms[j]), "seed %d rooms %d and %d apart" % [seed_value, i, j])


func test_each_floor_has_its_rooms_and_enemies():
	for number in range(1, floors.count() + 1):
		var spec := floors.spec(number)
		for seed_value in range(1, 21):
			var dungeon := Dungeon.generate(seed_value * 1009 + number, spec)
			assert_between(dungeon.rooms.size(), int(spec.rooms[0]), int(spec.rooms[1]), "floor %d seed %d rooms" % [number, seed_value])
			assert_gt(dungeon.spawns.size(), 0, "floor %d seed %d enemies" % [number, seed_value])
			for spawn in dungeon.spawns:
				assert_has(spec.enemies, spawn.kind)


func test_the_start_room_is_quiet_and_the_stairs_are_elsewhere():
	for seed_value in range(1, 41):
		var dungeon := Dungeon.generate(seed_value, floors.spec(1))
		assert_true(dungeon.rooms[0].has_point(dungeon.start))
		assert_false(dungeon.rooms[0].has_point(dungeon.stairs), "seed %d" % seed_value)
		for spawn in dungeon.spawns:
			assert_true(dungeon.is_floor(spawn.cell))
			assert_false(dungeon.rooms[0].has_point(spawn.cell), "seed %d: an enemy in the start room" % seed_value)
			assert_ne(spawn.cell, dungeon.stairs)


func test_the_same_seed_builds_the_same_floor():
	var first := Dungeon.generate(2026, floors.spec(1))
	var second := Dungeon.generate(2026, floors.spec(1))
	assert_eq(second.to_text(), first.to_text())


func test_seeds_that_differ_build_different_floors():
	var seen := {}
	for seed_value in range(100, 120):
		seen[Dungeon.generate(seed_value, floors.spec(1)).to_text()] = true
	assert_eq(seen.size(), 20)


## Seed 7 of floor 1, pinned: a change to the generator that moves it must say so here.
func test_seed_7_builds_the_pinned_floor():
	var dungeon := Dungeon.generate(7, floors.spec(1))
	assert_eq(dungeon.rooms.size(), 6)
	assert_eq(dungeon.rooms[0], Rect2i(22, 9, 5, 4))
	assert_eq(dungeon.start, Vector2i(24, 11))
	assert_eq(dungeon.stairs, Vector2i(10, 18))
	assert_eq(dungeon.floor_cells(), 170)
	assert_eq(dungeon.spawns.size(), 8)


func test_the_distance_field_counts_steps_round_walls():
	var dungeon := Dungeon.from_text(PackedStringArray([
		"#######",
		"#S..#>#",
		"#.#.#.#",
		"#.#...#",
		"#######",
	]))
	var field := dungeon.distance_field(dungeon.start)
	assert_eq(field[dungeon.index(Vector2i(3, 1))], 2)
	assert_eq(field[dungeon.index(dungeon.stairs)], 8)
	assert_eq(field[dungeon.index(Vector2i(1, 3))], 2)
	assert_eq(field[dungeon.index(Vector2i(4, 1))], -1, "a wall")


func test_a_line_is_clear_only_over_floor():
	var dungeon := Dungeon.from_text(PackedStringArray([
		"#######",
		"#.....#",
		"#..#..#",
		"#.....#",
		"#######",
	]))
	assert_true(dungeon.line_clear(Vector2i(1, 1), Vector2i(5, 1)))
	assert_false(dungeon.line_clear(Vector2i(1, 2), Vector2i(5, 2)), "the pillar is in the way")
	assert_true(dungeon.line_clear(Vector2i(1, 3), Vector2i(5, 3)))
	assert_true(dungeon.line_clear(Vector2i(2, 2), Vector2i(2, 2)))
