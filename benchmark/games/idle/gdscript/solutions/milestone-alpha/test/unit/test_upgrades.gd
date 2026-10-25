extends GutTest
## Upgrades: offered once their producer is owned often enough, they multiply it, the tap or everything.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_an_upgrade_waits_for_its_producer():
	assert_false(economy.upgrade_unlocked("twin_wicks"))
	economy.owned["wick_moth"] = 10
	assert_true(economy.upgrade_unlocked("twin_wicks"))


func test_an_upgrade_doubles_its_producer():
	economy.owned["wick_moth"] = 10
	economy.glow = 150.0
	var before := economy.producer_rate("wick_moth")
	assert_true(economy.buy_upgrade("twin_wicks"))
	assert_eq(economy.glow, 0.0)
	assert_almost_eq(economy.producer_rate("wick_moth"), before * 2.0, 1e-9)
	assert_false(economy.upgrade_unlocked("twin_wicks"), "bought once")


func test_warm_hands_multiplies_gather():
	economy.glow = 300.0
	assert_true(economy.buy_upgrade("warm_hands"))
	assert_eq(economy.tap_value(), 5.0)


func test_dusk_bloom_lifts_every_producer():
	for id in ["wick_moth", "glow_snail"]:
		economy.owned[id] = 25
	economy.glow = 1e6
	economy._dirty = true
	var before := economy.rate()
	assert_true(economy.buy_upgrade("dusk_bloom"))
	assert_almost_eq(economy.rate(), before * 1.5, 1e-6)
	assert_eq(economy.tap_value(), 1.0, "not the tap")
