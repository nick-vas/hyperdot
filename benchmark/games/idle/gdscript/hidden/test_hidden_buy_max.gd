extends GutTest
## Hidden check for the prototype's add-feature: Buy max. The most a glow pays for, exactly at a price boundary and with
## far more glow than a loop could count to, and the game's third buy mode.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_hidden_nothing_without_the_price_of_one():
	economy.glow = 9.99
	assert_eq(economy.max_affordable("wick_moth"), 0)
	assert_eq(economy.buy_max("wick_moth"), 0)
	assert_eq(economy.count("wick_moth"), 0)
	assert_eq(economy.glow, 9.99)


func test_hidden_the_most_the_glow_pays_for():
	for owned in [0, 3, 30]:
		for glow in [10.0, 99.0, 1234.5, 5e6]:
			economy.owned["wick_moth"] = owned
			economy.glow = glow
			var k := economy.max_affordable("wick_moth")
			if k > 0:
				assert_lte(economy.cost("wick_moth", k), glow, "%d at %d owned with %s" % [k, owned, glow])
			assert_gt(economy.cost("wick_moth", k + 1), glow, "%d at %d owned with %s" % [k + 1, owned, glow])


func test_hidden_an_exact_price_buys_the_last_one():
	for amount in [1, 2, 9, 17, 64]:
		economy.owned["glow_snail"] = 11
		economy.glow = economy.cost("glow_snail", amount)
		assert_eq(economy.max_affordable("glow_snail"), amount, "glow exactly the price of %d" % amount)


func test_hidden_vast_glow():
	economy.glow = 1e80
	var k := economy.max_affordable("firefly_choir")
	assert_gt(k, 1000)
	assert_lte(economy.cost("firefly_choir", k), 1e80)
	assert_gt(economy.cost("firefly_choir", k + 1), 1e80)


func test_hidden_buy_max_buys_and_spends_that_many():
	economy.owned["glow_snail"] = 4
	economy.glow = 50000.0
	var expected := economy.max_affordable("glow_snail")
	var price := economy.cost("glow_snail", expected)
	assert_eq(economy.buy_max("glow_snail"), expected)
	assert_eq(economy.count("glow_snail"), 4 + expected)
	assert_almost_eq(economy.glow, 50000.0 - price, 1e-6)


func test_hidden_the_mode_button_offers_max():
	var game: Control = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	var mode: Button = game.get_node("Safe/Column/Header/BuyModeButton")
	var seen := []
	for i in 3:
		seen.append(game.buy_mode)
		mode.pressed.emit()
	assert_eq(seen, [1, 10, 0])
	assert_eq(game.buy_mode, 1, "back to Buy 1 after Buy max")
	mode.pressed.emit()
	mode.pressed.emit()
	game.add_glow(1000.0)
	var expected := game.economy.max_affordable("wick_moth")
	game.get_node("Safe/Column/ProducerPage/List/WickMothRow/Box/BuyButton").pressed.emit()
	assert_eq(game.economy.count("wick_moth"), expected)
	assert_gt(expected, 10)
