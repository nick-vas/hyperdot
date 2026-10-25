extends GutTest
## Hidden check for the prototype's add-feature: Battle.sell(cell) gives back 70% of everything paid for the tower,
## rounded down, frees the cell, and the route and the pests on the field take the way it opens.

const FIELD := ["S...G", ".....", "....."]

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_a_new_tower_gives_back_70_percent():
	var battle := Battle.custom(catalog, FIELD, 200, 5, [])
	battle.place("thorn", Vector2i(2, 1))
	assert_eq(battle.sell(Vector2i(2, 1)), 35)
	assert_eq(battle.gold, 200 - 50 + 35)
	assert_false(battle.towers.has(Vector2i(2, 1)))
	assert_true(battle.map.is_open(Vector2i(2, 1)))


func test_hidden_upgrades_count_towards_the_refund():
	var battle := Battle.custom(catalog, FIELD, 1000, 5, [])
	battle.place("acorn", Vector2i(2, 2))
	battle.upgrade(Vector2i(2, 2))
	var paid := catalog.cost("acorn") + catalog.upgrade_cost("acorn", 2)
	assert_eq(battle.sell(Vector2i(2, 2)), floori(paid * 0.7))
	battle.place("thorn", Vector2i(1, 2))
	battle.upgrade(Vector2i(1, 2))
	battle.upgrade(Vector2i(1, 2))
	assert_eq(battle.sell(Vector2i(1, 2)), 112, "70% of 50 + 40 + 70")


func test_hidden_selling_never_makes_sap():
	for id in catalog.tower_ids:
		for level in [1, 2, 3]:
			var battle := Battle.custom(catalog, FIELD, 2000, 5, [])
			battle.place(id, Vector2i(2, 1))
			for i in level - 1:
				battle.upgrade(Vector2i(2, 1))
			battle.sell(Vector2i(2, 1))
			assert_lt(battle.gold, 2000, "%s level %d" % [id, level])


func test_hidden_the_route_and_the_pests_take_the_opened_way():
	var battle := Battle.custom(catalog, FIELD, 500, 5, [])
	battle.place("thorn", Vector2i(2, 0))
	var pest := battle.spawn_at("beetle", Vector2i(1, 1))
	pest.speed = 0.0
	assert_eq(battle.map.route.size(), 7)
	battle.sell(Vector2i(2, 0))
	assert_eq(battle.map.route.size(), 5)
	assert_eq(pest.path.size(), battle.map.path_from(pest.target()).size())
	assert_eq(pest.path[-1], battle.map.store)


func test_hidden_nothing_to_sell_gives_nothing():
	var battle := Battle.custom(catalog, FIELD, 200, 5, [])
	assert_eq(battle.sell(Vector2i(1, 1)), 0)
	assert_eq(battle.gold, 200)
	battle.place("thorn", Vector2i(1, 1))
	battle.phase = Battle.Phase.WON
	assert_eq(battle.sell(Vector2i(1, 1)), 0)
	assert_true(battle.towers.has(Vector2i(1, 1)))
