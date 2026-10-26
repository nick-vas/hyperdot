extends GutTest
## The rule of the field: no tower may leave the gate, or a pest on the field, without a way to the store.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_the_last_gap_cannot_be_planted():
	var battle := Battle.custom(catalog, ["S.#..", "..#..", "....G"], 500, 5, [])
	assert_false(battle.can_place("thorn", Vector2i(2, 2)))
	assert_false(battle.place("thorn", Vector2i(2, 2)))
	assert_eq(battle.gold, 500)
	assert_false(battle.map.route.is_empty())


func test_a_cell_with_a_way_round_it_can_be_planted():
	var battle := Battle.custom(catalog, ["S....", ".....", "....G"], 500, 5, [])
	assert_true(battle.place("thorn", battle.map.route[2]))


func test_a_wall_of_towers_always_leaves_a_gap():
	var battle := Battle.custom(catalog, ["S.....", "......", "......", ".....G"], 1000, 5, [])
	var planted := 0
	for y in 4:
		if battle.place("thorn", Vector2i(3, y)):
			planted += 1
	assert_eq(planted, 3)
	assert_eq(battle.map.route[-1], battle.map.store)
