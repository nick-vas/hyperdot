extends GutTest
## Economy's bulk buys: ten at once, and as many as the glow pays for.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_max_is_zero_without_the_price_of_one():
	economy.glow = 9.99
	assert_eq(economy.max_affordable("wick_moth"), 0)
	assert_eq(economy.buy_max("wick_moth"), 0)


func test_max_buys_as_many_as_the_glow_pays_for():
	economy.glow = 100.0
	var amount := economy.max_affordable("wick_moth")
	assert_eq(amount, 6)
	assert_lte(economy.cost("wick_moth", amount), 100.0)
	assert_gt(economy.cost("wick_moth", amount + 1), 100.0)
	assert_eq(economy.buy_max("wick_moth"), 6)
	assert_eq(economy.count("wick_moth"), 6)


func test_max_takes_the_last_one_at_an_exact_price():
	economy.owned["glow_snail"] = 12
	economy.glow = economy.cost("glow_snail", 9)
	assert_eq(economy.max_affordable("glow_snail"), 9)
	economy.buy_max("glow_snail")
	assert_eq(economy.glow, 0.0)


func test_max_with_a_vast_amount_of_glow():
	economy.glow = 1e60
	var amount := economy.max_affordable("wick_moth")
	assert_between(amount, 900, 1000)
	assert_lte(economy.cost("wick_moth", amount), 1e60)
	assert_gt(economy.cost("wick_moth", amount + 1), 1e60)
