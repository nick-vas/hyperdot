extends GutTest
## The game scene: Gather, the producer rows, the buy mode, the upgrade page and the dawn's panel.

var game: Control


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func _row(id: String) -> Node:
	return game.get_node("Safe/Column/ProducerPage/List/%sRow" % id.to_pascal_case())


func test_gather_adds_glow():
	game.get_node("Safe/Column/GatherButton").pressed.emit()
	assert_eq(game.economy.glow, 1.0)


func test_a_row_buys_its_producer():
	game.add_glow(10.0)
	await wait_physics_frames(1)
	var button: Button = _row("wick_moth").get_node("Box/BuyButton")
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(game.economy.count("wick_moth"), 1)
	await wait_physics_frames(1)
	assert_string_contains(_row("wick_moth").get_node("Box/Info/DetailLabel").text, "1")


func test_a_row_is_disabled_without_the_price():
	await wait_physics_frames(1)
	assert_true(_row("glow_snail").get_node("Box/BuyButton").disabled)


func test_the_mode_button_steps_through_one_ten_and_max():
	var mode: Button = game.get_node("Safe/Column/Header/BuyModeButton")
	assert_eq(game.buy_mode, 1)
	mode.pressed.emit()
	assert_eq(game.buy_mode, 10)
	game.add_glow(1000.0)
	_row("wick_moth").get_node("Box/BuyButton").pressed.emit()
	assert_eq(game.economy.count("wick_moth"), 10)
	mode.pressed.emit()
	assert_eq(game.buy_mode, 0)
	mode.pressed.emit()
	assert_eq(game.buy_mode, 1)


func test_the_upgrade_page_shows_what_is_on_offer():
	game.get_node("Safe/Column/Bar/UpgradesTab").pressed.emit()
	assert_true(game.get_node("Safe/Column/UpgradePage").visible)
	assert_false(game.get_node("Safe/Column/ProducerPage").visible)
	await wait_physics_frames(1)
	assert_true(game.get_node("Safe/Column/UpgradePage/List/WarmHandsRow").visible)
	assert_false(game.get_node("Safe/Column/UpgradePage/List/TwinWicksRow").visible)


func test_the_dawn_asks_first():
	var dawn: Button = game.get_node("Safe/Column/Bar/DawnButton")
	await wait_physics_frames(1)
	assert_true(dawn.disabled)
	game.add_glow(4e6)
	await wait_physics_frames(1)
	assert_false(dawn.disabled)
	dawn.pressed.emit()
	assert_true(game.get_node("DawnPanel").visible)
	game.get_node("DawnPanel/Box/ConfirmButton").pressed.emit()
	assert_false(game.get_node("DawnPanel").visible)
	assert_eq(game.economy.embers, 2.0)
	assert_eq(game.economy.glow, 0.0)


func test_time_away_is_shown_and_collected():
	game.show_welcome(7500.0, 12345.0)
	await wait_physics_frames(1)
	assert_true(game.get_node("WelcomePanel").visible)
	assert_string_contains(game.get_node("WelcomePanel/Box/MessageLabel").text, "2 h 05 min")
	assert_string_contains(game.get_node("WelcomePanel/Box/MessageLabel").text, "12.3K")
	game.get_node("WelcomePanel/Box/CollectButton").pressed.emit()
	assert_false(game.get_node("WelcomePanel").visible)


func test_production_runs_in_physics_ticks():
	game.economy.owned["glow_snail"] = 3
	game.economy._dirty = true
	await wait_physics_frames(60)
	assert_between(game.economy.glow, 11.0, 13.0)
