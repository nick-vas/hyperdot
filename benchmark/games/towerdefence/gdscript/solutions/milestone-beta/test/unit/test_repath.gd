extends GutTest
## Pests on the field take a new tower into account at once: each turns onto the shortest way left from the cell it is
## heading to, and none walks into a tower.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_pests_on_the_field_go_round_a_new_tower():
	var battle := Battle.custom(catalog, ["S.......", "........", ".......G"], 500, 10, [])
	var pest := battle.spawn_at("beetle", Vector2i(1, 0))
	pest.hp = 100000
	var ahead: Vector2i = pest.path[3]
	assert_true(battle.place("thorn", ahead))
	assert_false(pest.path.has(ahead))
	assert_eq(pest.path[-1], battle.map.store)
	var lives := battle.lives
	var entered := false
	for i in 1200:
		battle.step()
		entered = entered or pest.cell() == ahead
		if not pest.alive:
			break
	assert_false(entered, "it never stood on the tower's cell")
	assert_eq(battle.lives, lives - pest.leak, "it reached the store")
