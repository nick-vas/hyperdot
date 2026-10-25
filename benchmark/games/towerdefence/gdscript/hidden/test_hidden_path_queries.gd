extends GutTest
## Hidden check for the beta's fix-performance: towers choose their target without searching paths, so a field full of
## pests costs no path search at all between placements; the leading pest in range is still the one shot.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_a_full_field_searches_no_paths():
	var battle := Battle.create(catalog, "meadow", 1)
	battle.gold = 5000
	battle.lives = 100000
	var placed := 0
	for cell in [Vector2i(2, 3), Vector2i(4, 3), Vector2i(6, 3), Vector2i(8, 3), Vector2i(10, 5), Vector2i(12, 5), Vector2i(5, 6), Vector2i(9, 2)]:
		if battle.place(["thorn", "puff", "acorn"][placed % 3], cell):
			placed += 1
	assert_gte(placed, 6)
	for i in 80:
		var pest := battle.spawn_at(["aphid", "beetle"][i % 2], battle.map.route[i % 8])
		pest.hp = 1000000
	var before := battle.map.path_queries
	for i in 300:
		battle.step()
	assert_lte(battle.map.path_queries - before, 150, "path searches in 300 ticks with 80 pests and no placement")
	assert_gt(battle.shots.size() + battle.range_checks, 0)


func test_hidden_the_leading_pest_in_range_is_shot():
	var battle := Battle.custom(catalog, ["S..........G", "............"], 500, 10, [])
	battle.place("thorn", Vector2i(5, 1))
	var pests: Array[Enemy] = []
	for x in [2, 3, 4, 6, 7, 9]:
		var pest := battle.spawn_at("beetle", Vector2i(x, 0))
		pest.speed = 0.0
		pest.hp = 1000
		pests.append(pest)
	battle.step()
	assert_eq(battle.shots.size(), 1)
	assert_eq(battle.shots[0].target, pests[4], "x = 7 is in range and closest to the store; x = 9 is out of range")


func test_hidden_the_target_is_the_one_furthest_along_its_own_way():
	var battle := Battle.custom(catalog, ["S...", "....", "...G"], 500, 10, [])
	battle.place("thorn", Vector2i(1, 1))
	var behind := battle.spawn_at("beetle", Vector2i(0, 2))
	var ahead := battle.spawn_at("beetle", Vector2i(2, 2))
	ahead.pos.x += 0.3
	for pest in [behind, ahead]:
		pest.speed = 0.0
		pest.hp = 1000
	battle.step()
	assert_eq(battle.shots[0].target, ahead)
