extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the Briar Maze and its slug queen, the moth, and three fair maps.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_the_briar_maze_ends_with_the_slug_queen():
	assert_eq(catalog.map_count(), 3)
	assert_eq(catalog.map_at(3).id, "briar")
	var waves := catalog.waves_for("briar")
	assert_eq(waves.size(), 6)
	var found := false
	for group: Dictionary in waves[5].groups:
		found = found or group.enemy == "slug_queen"
	assert_true(found)
	assert_between(int(catalog.enemies["slug_queen"].hp), 600, 2400)
	assert_eq(int(catalog.enemies["slug_queen"].leak), 20)


func test_hidden_the_moth_is_the_fastest_pest():
	for id in catalog.enemies:
		if id != "moth":
			assert_lt(float(catalog.enemies[id].speed), float(catalog.enemies["moth"].speed), id)


func test_hidden_every_map_is_fair():
	for row in catalog.maps:
		for seed_value in [1, 2, 3]:
			var battle := Battle.create(catalog, row.id, seed_value)
			assert_true(Bot.play(battle), "%s, seed %d: lost at wave %d" % [row.id, seed_value, battle.wave])
		assert_false(Bot.idle(Battle.create(catalog, row.id, 1)), row.id)
