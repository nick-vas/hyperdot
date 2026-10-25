extends GutTest
## Hidden check for the beta's fix-playthrough: everything the hive makes counts toward the dawn and toward the glow
## earned in all runs, spending never lowers the dawn, and the dawn is no cheaper than before.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())
	economy.owned["moon_lily"] = 20
	economy._dirty = true


func test_hidden_production_counts_toward_the_dawn():
	var made := economy.tick(1000.0)
	assert_gt(made, 0.0)
	assert_almost_eq(economy.run_earned, made, made * 1e-12)
	assert_almost_eq(economy.total_earned, made, made * 1e-12)


func test_hidden_time_away_counts_toward_the_dawn():
	var away := Offline.apply(economy, 0.0, 7200.0)
	assert_almost_eq(economy.run_earned, float(away.glow), 1e-6)
	assert_almost_eq(economy.total_earned, float(away.glow), 1e-6)


func test_hidden_spending_does_not_lower_the_dawn():
	economy.tick(1000.0)
	var gain := economy.dawn_gain()
	assert_gte(gain, 1.0)
	economy.buy_max("star_loom")
	economy.buy_max("moon_lily")
	assert_eq(economy.dawn_gain(), gain)


func test_hidden_the_dawn_costs_what_it_did():
	var fresh := Economy.new(Catalog.from_files())
	fresh.earn(999999.0)
	assert_eq(fresh.dawn_gain(), 0.0)
	fresh.earn(1.0)
	assert_eq(fresh.dawn_gain(), 1.0)
	fresh.earn(8e6)
	assert_eq(fresh.dawn_gain(), 3.0)


func test_hidden_the_bot_greets_three_dawns_within_an_hour():
	var bot := Economy.new(Catalog.from_files())
	for second in 3600:
		Bot.act(bot)
		bot.tick(1.0)
	assert_gte(bot.dawns, 3)
	assert_lt(bot.dawns, 12, "not trivial")
