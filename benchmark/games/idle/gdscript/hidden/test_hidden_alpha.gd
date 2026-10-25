extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: the Moon Lily, Buy max, upgrades on their own page, the dawn,
## and a save that Main reads at start, paying the time away up to eight hours and nothing for a clock set back.

const PATH := "user://test_hidden_alpha.json"

var now := 1761000000.0


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _open() -> Control:
	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = PATH
	main.clock = func() -> float: return now
	add_child_autofree(main)
	await wait_physics_frames(1)
	main.game.set_physics_process(false)
	return main


func test_hidden_four_producers_and_their_upgrades():
	var catalog := Catalog.from_files()
	var ids := catalog.producers.map(func(p: Dictionary) -> String: return str(p.id))
	assert_eq(ids.slice(0, 4), ["wick_moth", "glow_snail", "firefly_choir", "moon_lily"])
	var economy := Economy.new(catalog)
	economy.owned["wick_moth"] = 10
	economy.glow = 1e4
	var before := economy.producer_rate("wick_moth")
	assert_true(economy.buy_upgrade("twin_wicks"))
	assert_almost_eq(economy.producer_rate("wick_moth"), before * 2.0, 1e-9)


func test_hidden_buy_max():
	var economy := Economy.new(Catalog.from_files())
	economy.glow = 100.0
	assert_eq(economy.max_affordable("wick_moth"), 6)
	assert_eq(economy.buy_max("wick_moth"), 6)


func test_hidden_the_dawn():
	var economy := Economy.new(Catalog.from_files())
	economy.earn(9e6)
	economy.buy("wick_moth")
	assert_eq(economy.dawn(), 3.0)
	assert_eq(economy.glow, 0.0)
	assert_eq(economy.owned.size(), 0)
	economy.owned["wick_moth"] = 2
	economy._dirty = true
	assert_almost_eq(economy.rate(), 2 * 0.5 * 1.3, 1e-9)


func test_hidden_a_save_comes_back_with_the_time_away():
	var main := await _open()
	main.game.economy.owned["glow_snail"] = 5
	main.game.economy._dirty = true
	main.game.economy.embers = 2.0
	main.game.economy.glow = 1e20
	main.save_now()
	remove_child(main)
	main.queue_free()
	now += 3600.0
	main = await _open()
	assert_eq(main.game.economy.count("glow_snail"), 5)
	assert_eq(main.game.economy.embers, 2.0)
	assert_true(Numbers.close(main.game.economy.glow, 1e20 + 3600.0 * 20.0 * 1.2, 1e-12))
	assert_true(main.get_node("Game/WelcomePanel").visible)


func test_hidden_time_away_is_capped_and_a_clock_set_back_pays_nothing():
	var main := await _open()
	main.game.economy.owned["glow_snail"] = 5
	main.game.economy._dirty = true
	main.save_now()
	remove_child(main)
	main.queue_free()
	now -= 86400.0
	main = await _open()
	assert_almost_eq(main.game.economy.glow, 0.0, 1.0)
	remove_child(main)
	main.queue_free()
	now += 40.0 * 86400.0
	main = await _open()
	assert_almost_eq(main.game.economy.glow, 28800.0 * 20.0, 1.0)


func test_hidden_settings_open_and_close():
	var main := await _open()
	main.get_node("Game/Safe/Column/Bar/SettingsButton").pressed.emit()
	await wait_frames(1)
	assert_not_null(main.get_node_or_null("Settings"))
	main.get_node("Settings/Safe/Box/BackButton").pressed.emit()
	await wait_frames(2)
	assert_null(main.get_node_or_null("Settings"))
	assert_true(main.get_node("Game").visible)
