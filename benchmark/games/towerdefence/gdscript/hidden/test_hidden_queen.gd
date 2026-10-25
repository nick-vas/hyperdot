extends GutTest
## Hidden check for the beta's fix-playthrough: the slug queen is a boss the bot can beat, not a wall, and not a
## pushover; the Briar Maze stays fair.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_the_queen_is_the_toughest_pest_within_reason():
	var queen: Dictionary = catalog.enemies["slug_queen"]
	assert_between(int(queen.hp), 600, 2400)
	for id in catalog.enemies:
		if id != "slug_queen":
			assert_gt(int(queen.hp), int(catalog.enemies[id].hp) * 5, id)


func test_hidden_the_queen_ends_the_briar_maze():
	var waves := catalog.waves_for("briar")
	assert_eq(waves.size(), 6)
	var found := false
	for group: Dictionary in waves[5].groups:
		found = found or group.enemy == "slug_queen"
	assert_true(found)


func test_hidden_the_briar_maze_is_fair():
	for seed_value in [1, 2, 3]:
		var battle := Battle.create(catalog, "briar", seed_value)
		assert_true(Bot.play(battle), "seed %d: lost at wave %d" % [seed_value, battle.wave])
	assert_false(Bot.idle(Battle.create(catalog, "briar", 1)))
