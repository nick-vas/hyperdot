extends GutTest
## Hidden check for the prototype's fix-bug: no tower may leave the gate, or any pest on the field, without a way to the
## store; a cell with a way round it may still be planted, on the route or not.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_the_last_gap_is_refused():
	var battle := Battle.custom(catalog, ["S.#..", "..#..", "....G"], 500, 5, [])
	assert_false(battle.can_place("thorn", Vector2i(2, 2)))
	assert_false(battle.place("thorn", Vector2i(2, 2)))
	assert_eq(battle.gold, 500)
	assert_false(battle.towers.has(Vector2i(2, 2)))
	assert_eq(battle.map.route[-1], battle.map.store)


func test_hidden_a_route_cell_with_a_way_round_is_allowed():
	var battle := Battle.custom(catalog, ["S....", ".....", "....G"], 500, 5, [])
	var cell: Vector2i = battle.map.route[2]
	assert_true(battle.can_place("thorn", cell))
	assert_true(battle.place("thorn", cell))
	assert_false(battle.map.route.has(cell))


func test_hidden_a_wall_across_the_field_keeps_a_gap():
	var battle := Battle.custom(catalog, ["S.....", "......", "......", ".....G"], 1000, 5, [])
	var planted := 0
	for y in 4:
		if battle.place("thorn", Vector2i(3, y)):
			planted += 1
	assert_eq(planted, 3)
	assert_false(battle.map.route.is_empty())


func test_hidden_a_pest_on_the_field_is_never_cut_off():
	var battle := Battle.custom(catalog, ["S....", "###..", "....G"], 500, 5, [])
	var pest := battle.spawn_at("beetle", Vector2i(0, 2))
	pest.speed = 0.0
	assert_false(battle.place("thorn", Vector2i(3, 2)), "the corner the pest is in has no other way out")
	assert_eq(battle.towers.size(), 0)
	assert_eq(battle.gold, 500)
	assert_eq(pest.path[-1], battle.map.store)


func test_hidden_the_wave_still_ends_after_a_refused_tower():
	var wave := {"number": 1, "bonus": 0, "groups": [{"enemy": "aphid", "count": 4, "gap": 20, "delay": 0}]}
	var battle := Battle.custom(catalog, ["S.#..", "..#..", "....G"], 500, 20, [wave])
	battle.start_wave()
	for i in 60:
		battle.step()
	battle.place("thorn", Vector2i(2, 2))
	while not battle.is_over() and battle.ticks < 3000:
		battle.step()
	assert_eq(battle.phase, Battle.Phase.WON)
	assert_eq(battle.leaks, 4)
