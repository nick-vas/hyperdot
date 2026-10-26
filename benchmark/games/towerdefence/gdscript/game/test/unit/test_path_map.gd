extends GutTest
## PathMap: the route from the gate to the store, rocks and towers in its way, and what a tower would block.

const FIELD := [
	"S.#.....",
	"..#.##..",
	"....#..G",
]


func test_the_route_runs_from_the_gate_to_the_store():
	var map := PathMap.from_rows(FIELD)
	assert_eq(map.route[0], Vector2i(0, 0))
	assert_eq(map.route[-1], Vector2i(7, 2))
	assert_eq(map.route.size(), 14, "the shortest way round the rocks")


func test_rocks_are_never_on_the_route():
	var map := PathMap.from_rows(FIELD)
	for cell in map.route:
		assert_false(map.is_rock(cell))


func test_a_tower_moves_the_route_and_selling_it_restores_it():
	var map := PathMap.from_rows(["S...G", ".....", "....."])
	assert_eq(map.route.size(), 5)
	map.set_tower(Vector2i(2, 0), true)
	assert_false(map.route.has(Vector2i(2, 0)))
	assert_eq(map.route.size(), 7)
	map.set_tower(Vector2i(2, 0), false)
	assert_eq(map.route.size(), 5)


func test_the_gate_and_the_store_cannot_be_built_on():
	var map := PathMap.from_rows(FIELD)
	assert_false(map.is_buildable(map.gate))
	assert_false(map.is_buildable(map.store))
	assert_false(map.is_buildable(Vector2i(2, 0)), "a rock")
	assert_true(map.is_buildable(Vector2i(1, 0)))


func test_a_tower_in_the_last_gap_blocks():
	var map := PathMap.from_rows(["S.#..", "..#..", "....G"])
	assert_true(map.blocks(Vector2i(2, 2), []))
	assert_false(map.blocks(Vector2i(1, 1), []))


func test_a_tower_that_cuts_a_cell_off_blocks_it():
	var map := PathMap.from_rows(["S....", "###..", "....G"])
	assert_false(map.blocks(Vector2i(3, 2), []))
	assert_true(map.blocks(Vector2i(3, 2), [Vector2i(1, 2)]), "the corner beyond it has no other way out")


func test_checks_leave_the_map_as_it_was():
	var map := PathMap.from_rows(FIELD)
	var before := map.route.duplicate()
	map.blocks(Vector2i(3, 2), [])
	map.preview_route(Vector2i(3, 2))
	assert_eq(map.route, before)
	assert_true(map.is_open(Vector2i(3, 2)))
	assert_eq(map.path_from(map.gate), before)


func test_a_path_from_a_rock_is_empty():
	var map := PathMap.from_rows(FIELD)
	assert_eq(map.path_from(Vector2i(2, 0)).size(), 0)
