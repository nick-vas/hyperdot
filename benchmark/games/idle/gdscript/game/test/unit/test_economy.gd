extends GutTest
## Economy: prices that grow by each producer's growth, buying, production over time and Gather.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_the_first_of_a_producer_costs_its_base_price():
	assert_eq(economy.cost("wick_moth"), 10.0)
	assert_eq(economy.cost("glow_snail"), 120.0)


func test_each_one_owned_raises_the_price_by_the_growth():
	economy.owned["wick_moth"] = 3
	assert_almost_eq(economy.cost("wick_moth"), 10.0 * 1.15 * 1.15 * 1.15, 1e-9)


func test_buying_spends_the_price_and_adds_one():
	economy.glow = 25.0
	assert_true(economy.buy("wick_moth"))
	assert_eq(economy.count("wick_moth"), 1)
	assert_almost_eq(economy.glow, 15.0, 1e-9)


func test_too_little_glow_buys_nothing():
	economy.glow = 9.0
	assert_false(economy.buy("wick_moth"))
	assert_eq(economy.count("wick_moth"), 0)
	assert_eq(economy.glow, 9.0)


func test_an_unknown_producer_cannot_be_bought():
	economy.glow = 1e9
	assert_false(economy.buy("lamp_post"))


func test_production_is_the_rate_times_the_seconds():
	economy.owned["wick_moth"] = 4
	economy.owned["glow_snail"] = 1
	economy._dirty = true
	assert_almost_eq(economy.rate(), 4 * 0.5 + 4.0, 1e-9)
	economy.tick(10.0)
	assert_almost_eq(economy.glow, 60.0, 1e-9)


func test_every_25_of_a_producer_double_it():
	economy.owned["wick_moth"] = 25
	economy._dirty = true
	assert_almost_eq(economy.producer_rate("wick_moth"), 25 * 0.5 * 2.0, 1e-9)


func test_gather_gives_the_tap_value():
	assert_eq(economy.tap(), 1.0)
	assert_eq(economy.glow, 1.0)


func test_a_long_tick_and_many_short_ones_agree_within_the_tolerance():
	economy.owned["star_loom"] = 300
	economy.embers = 1e6
	economy._dirty = true
	var other := Economy.from_dict(economy.catalog, economy.to_dict())
	economy.tick(3600.0)
	for i in 3600 * 4:
		other.tick(0.25)
	assert_gt(economy.glow, 9007199254740992.0, "past 2^53")
	assert_true(Numbers.close(economy.glow, other.glow, Numbers.TOLERANCE), "%s and %s" % [economy.glow, other.glow])


func test_glow_stops_at_the_most_a_double_can_keep():
	economy.earn(1e308)
	economy.earn(1e308)
	assert_eq(economy.glow, Numbers.MAX)
	assert_false(is_inf(economy.glow))
