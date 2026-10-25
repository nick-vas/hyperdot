extends GutTest
## The game scene: Gather, the producer rows and the buy mode.

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
	var button: Button = _row("wick_moth").get_node("Box/BuyButton")
	assert_false(button.disabled)
	button.pressed.emit()
	assert_eq(game.economy.count("wick_moth"), 1)
	assert_string_contains(_row("wick_moth").get_node("Box/Info/DetailLabel").text, "1 owned")


func test_a_row_is_disabled_without_the_price():
	await wait_physics_frames(1)
	assert_true(_row("glow_snail").get_node("Box/BuyButton").disabled)


func test_the_mode_button_switches_between_one_and_ten():
	var mode: Button = game.get_node("Safe/Column/Header/BuyModeButton")
	assert_eq(game.buy_mode, 1)
	mode.pressed.emit()
	assert_eq(game.buy_mode, 10)
	assert_eq(mode.text, "Buy 10")
	game.add_glow(1000.0)
	_row("wick_moth").get_node("Box/BuyButton").pressed.emit()
	assert_eq(game.economy.count("wick_moth"), 10)


func test_production_runs_in_physics_ticks():
	game.economy.owned["glow_snail"] = 3
	game.economy._dirty = true
	await wait_physics_frames(60)
	assert_between(game.economy.glow, 11.0, 13.0)
