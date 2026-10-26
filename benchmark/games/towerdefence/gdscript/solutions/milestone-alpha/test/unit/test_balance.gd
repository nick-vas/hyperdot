extends GutTest
## Balance: the bot's build clears every map over several seeds without having it easy, and a field with no tower
## loses every map early.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_the_bot_clears_every_map():
	for row in catalog.maps:
		for seed_value in [1, 2, 3]:
			var battle := Battle.create(catalog, row.id, seed_value)
			assert_true(Bot.play(battle), "%s, seed %d: lost at wave %d" % [row.id, seed_value, battle.wave])


func test_the_campaign_costs_the_bot_some_seeds():
	var lost := 0
	for row in catalog.maps:
		var battle := Battle.create(catalog, row.id, 1)
		Bot.play(battle)
		lost += battle.start_lives - battle.lives
	assert_between(lost, 1, 30, "lost along the way")


func test_no_tower_loses_every_map_before_its_last_wave():
	for row in catalog.maps:
		var battle := Battle.create(catalog, row.id, 1)
		assert_false(Bot.idle(battle), row.id)
		assert_lt(battle.wave, battle.waves.size(), row.id)
