extends GutTest
## Hidden check for the beta's fix-performance: the rate is worked out once per change, not every tick, and is still
## right at once after every kind of change.

var game: Control


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	for p: Dictionary in game.economy.catalog.producers:
		game.economy.owned[str(p.id)] = 30
	game.economy._dirty = true


func _expected(economy: Economy) -> float:
	var total := 0.0
	for p: Dictionary in economy.catalog.producers:
		total += economy.unit_rate(str(p.id)) * economy.count(str(p.id))
	return total


func test_hidden_ticks_alone_work_nothing_out_again():
	await wait_physics_frames(2)
	var before: int = game.economy.rate_computations
	await wait_physics_frames(600)
	assert_lte(game.economy.rate_computations - before, 1)


func test_hidden_a_purchase_works_it_out_once_or_twice():
	await wait_physics_frames(2)
	game.add_glow(1e9)
	var before: int = game.economy.rate_computations
	game.buy("glow_snail")
	await wait_physics_frames(30)
	assert_between(game.economy.rate_computations - before, 1, 2)


func test_hidden_the_rate_is_right_at_once_after_a_purchase():
	var economy: Economy = game.economy
	economy.rate()
	economy.glow = 1e12
	var rate_before := economy.rate()
	economy.buy("star_loom")
	assert_gt(economy.rate(), rate_before)
	assert_true(Numbers.close(economy.rate(), _expected(economy), 1e-9))
	var earned := economy.tick(1.0)
	assert_true(Numbers.close(earned, _expected(economy), 1e-9), "the next tick pays the new rate")


func test_hidden_the_rate_is_right_at_once_after_an_upgrade_and_a_dawn():
	var economy: Economy = game.economy
	economy.rate()
	economy.glow = 1e12
	assert_true(economy.buy_upgrade("twin_wicks"))
	assert_true(Numbers.close(economy.producer_rate("wick_moth"), 0.5 * 30 * 2.0 * 2.0, 1e-9))
	economy.earn(4e6)
	economy.dawn()
	assert_eq(economy.rate(), 0.0)
	assert_eq(economy.tick(10.0), 0.0)


func test_hidden_a_loaded_economy_starts_with_its_rate():
	var economy := Economy.from_dict(game.economy.catalog, {"owned": {"glow_snail": 5}})
	assert_almost_eq(economy.tick(2.0), 40.0, 1e-9)
	var before := economy.rate_computations
	for i in 1000:
		economy.tick(1.0 / 60.0)
	assert_lte(economy.rate_computations - before, 1)
