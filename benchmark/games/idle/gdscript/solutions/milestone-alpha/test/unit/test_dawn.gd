extends GutTest
## The dawn: embers for the square root of a run's glow, everything else reset, and each ember adding to production.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_no_dawn_before_a_million_glow_earned():
	economy.earn(999999.0)
	assert_false(economy.can_dawn())
	assert_eq(economy.dawn(), 0.0)


func test_the_gain_is_the_square_root_of_the_run_in_millions():
	economy.earn(4e6)
	assert_eq(economy.dawn_gain(), 2.0)
	economy.earn(5e6)
	assert_eq(economy.dawn_gain(), 3.0)


func test_a_dawn_resets_the_run_and_keeps_embers():
	economy.earn(9e6)
	economy.buy("wick_moth")
	economy.owned["glow_snail"] = 10
	economy.upgrades["warm_hands"] = true
	assert_eq(economy.dawn(), 3.0)
	assert_eq(economy.embers, 3.0)
	assert_eq(economy.dawns, 1)
	assert_eq(economy.glow, 0.0)
	assert_eq(economy.run_earned, 0.0)
	assert_eq(economy.total_earned, 9e6)
	assert_eq(economy.owned.size(), 0)
	assert_eq(economy.upgrades.size(), 0)


func test_each_ember_adds_a_tenth():
	economy.embers = 5.0
	economy.owned["wick_moth"] = 2
	economy._dirty = true
	assert_almost_eq(economy.rate(), 2 * 0.5 * 1.5, 1e-9)


func test_spending_does_not_lower_the_dawn():
	economy.earn(4e6)
	economy.buy_max("glow_snail")
	assert_eq(economy.dawn_gain(), 2.0)
