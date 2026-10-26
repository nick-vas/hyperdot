extends GutTest
## Selling a tower: the cell is free again, some sap comes back, and the route takes the way it opens.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_selling_frees_the_cell_and_pays_some_sap_back():
	var battle := Battle.custom(catalog, ["S...G", "....."], 200, 5, [])
	battle.place("thorn", Vector2i(2, 1))
	var before := battle.gold
	var back := battle.sell(Vector2i(2, 1))
	assert_gt(back, 0)
	assert_eq(battle.gold, before + back)
	assert_false(battle.towers.has(Vector2i(2, 1)))
	assert_true(battle.map.is_open(Vector2i(2, 1)))


func test_selling_a_tower_on_the_old_route_shortens_it():
	var battle := Battle.custom(catalog, ["S...G", ".....", "....."], 200, 5, [])
	battle.place("thorn", Vector2i(2, 0))
	assert_eq(battle.map.route.size(), 7)
	battle.sell(Vector2i(2, 0))
	assert_eq(battle.map.route.size(), 5)


func test_nothing_to_sell_on_an_empty_cell():
	var battle := Battle.custom(catalog, ["S...G", "....."], 200, 5, [])
	assert_eq(battle.sell(Vector2i(1, 1)), 0)
	assert_eq(battle.gold, 200)
