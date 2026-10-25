extends GutTest
## Hidden check for the prototype's fix-bug: a bulk price is the sum of the single prices it stands for, at every count
## owned, and Buy 10 in the game spends exactly that.


func _singles(economy: Economy, id: String, amount: int) -> float:
	var copy := Economy.new(economy.catalog)
	copy.owned = economy.owned.duplicate()
	copy.glow = Numbers.MAX
	var total := 0.0
	for i in amount:
		total += copy.cost(id, 1)
		copy.buy(id, 1)
	return total


func test_hidden_a_bulk_price_is_the_sum_of_its_single_prices():
	var economy := Economy.new(Catalog.from_files())
	for p: Dictionary in economy.catalog.producers:
		var id := str(p.id)
		for owned in [0, 7, 40]:
			economy.owned[id] = owned
			for amount in [2, 10, 25]:
				var singles := _singles(economy, id, amount)
				assert_true(Numbers.close(economy.cost(id, amount), singles, 1e-9), "%s x%d at %d owned: %s, singles %s" % [id, amount, owned, economy.cost(id, amount), singles])


func test_hidden_the_single_price_is_unchanged():
	var economy := Economy.new(Catalog.from_files())
	assert_eq(economy.cost("glow_snail", 1), 120.0)
	economy.owned["glow_snail"] = 2
	assert_almost_eq(economy.cost("glow_snail", 1), 120.0 * 1.15 * 1.15, 1e-9)


func test_hidden_buy_10_spends_the_ten_single_prices():
	var game: Control = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.set_physics_process(false)
	var expected := _singles(game.economy, "glow_snail", 10)
	game.economy.glow = expected
	game.buy_mode = 10
	game._refresh()
	var button: Button = game.get_node("Safe/Column/ProducerPage/List/GlowSnailRow/Box/BuyButton")
	assert_false(button.disabled, "ten singles' worth of glow pays for Buy 10")
	button.pressed.emit()
	assert_eq(game.economy.count("glow_snail"), 10)
	assert_almost_eq(game.economy.glow, 0.0, expected * 1e-9)
