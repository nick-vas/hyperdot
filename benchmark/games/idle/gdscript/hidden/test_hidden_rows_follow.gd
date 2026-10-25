extends GutTest
## Hidden check for the alpha's fix-architecture: the producer rows still follow the economy, a buy, the buy mode and a
## dawn, and a row shows what it is given wherever it sits in the tree.

var game: Control


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)


func _row(id: String) -> Node:
	return game.get_node("Safe/Column/ProducerPage/List/%sRow" % id.to_pascal_case())


func test_hidden_a_row_lights_up_once_it_can_be_paid_for():
	assert_true(_row("wick_moth").get_node("Box/BuyButton").disabled)
	game.add_glow(10.0)
	await wait_frames(2)
	assert_false(_row("wick_moth").get_node("Box/BuyButton").disabled)


func test_hidden_a_row_counts_what_is_bought():
	game.add_glow(1000.0)
	game.buy("glow_snail")
	await wait_frames(2)
	assert_string_contains(_row("glow_snail").get_node("Box/Info/DetailLabel").text, "1 owned")
	assert_string_contains(_row("glow_snail").get_node("Box/BuyButton").text, "138")


func test_hidden_a_row_follows_the_buy_mode():
	game.next_mode()
	await wait_frames(2)
	assert_string_contains(_row("wick_moth").get_node("Box/BuyButton").text, "Buy 10")


func test_hidden_a_dawn_empties_the_rows():
	game.add_glow(1000.0)
	game.buy("wick_moth")
	game.add_glow(1e6)
	game.confirm_dawn()
	await wait_frames(2)
	assert_string_contains(_row("wick_moth").get_node("Box/Info/DetailLabel").text, "0 owned")


func test_hidden_a_row_alone_shows_what_it_is_given():
	var economy := Economy.new(Catalog.from_files())
	economy.owned["moon_lily"] = 3
	var row := ProducerRow.new()
	row.setup(economy.catalog.producer("moon_lily"))
	add_child_autofree(row)
	row.refresh(economy, 1)
	await wait_frames(2)
	assert_string_contains(row.get_node("Box/Info/DetailLabel").text, "3 owned")
	assert_engine_error_count(0)
