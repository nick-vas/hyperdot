extends GutTest
## Economy's rules: prices, purchases and production.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_a_price_grows_by_the_growth_for_each_one_owned():
	assert_eq(economy.cost("glow_snail"), 120.0)
	economy.owned["glow_snail"] = 4
	assert_almost_eq(economy.cost("glow_snail"), 120.0 * pow(1.15, 4), 1e-9)


func test_several_cost_the_sum_of_their_single_prices():
	economy.owned["wick_moth"] = 3
	var total := 0.0
	for i in 10:
		total += 10.0 * pow(1.15, 3 + i)
	assert_almost_eq(economy.cost("wick_moth", 10), total, total * 1e-12)


func test_a_purchase_spends_its_price_and_adds_what_was_bought():
	economy.glow = 1000.0
	var price := economy.cost("wick_moth", 5)
	assert_true(economy.buy("wick_moth", 5))
	assert_eq(economy.count("wick_moth"), 5)
	assert_almost_eq(economy.glow, 1000.0 - price, 1e-9)


func test_nothing_is_bought_without_the_price():
	economy.glow = 119.0
	assert_false(economy.buy("glow_snail"))
	assert_eq(economy.count("glow_snail"), 0)
	assert_eq(economy.glow, 119.0)
	economy.glow = 50.0
	assert_false(economy.buy("wick_moth", 5), "five cost more than 50")


func test_the_rate_is_each_producer_times_how_many():
	economy.owned["wick_moth"] = 3
	economy.owned["firefly_choir"] = 2
	economy._dirty = true
	assert_almost_eq(economy.rate(), 3 * 0.5 + 2 * 30.0, 1e-9)


func test_a_tick_pays_the_rate_times_the_seconds():
	economy.owned["glow_snail"] = 2
	economy._dirty = true
	assert_almost_eq(economy.tick(2.5), 20.0, 1e-9)
	assert_almost_eq(economy.glow, 20.0, 1e-9)
