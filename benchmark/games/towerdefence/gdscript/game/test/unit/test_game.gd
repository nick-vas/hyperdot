extends GutTest
## The game scene: a battle fed ticks on the field, building from the HUD, the next wave, and the result panel.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_map(1, 7)
	await wait_physics_frames(2)


func test_a_map_starts_with_its_sap_and_seeds():
	assert_eq(game.level, 1)
	assert_eq(game.phase, "Build")
	assert_eq(game.gold, 120)
	assert_eq(game.get_node("HUD/GoldLabel").text, "Sap: 120")
	assert_eq(game.get_node("HUD/LivesLabel").text, "Seeds: 20")


func test_a_tower_button_then_a_cell_builds_that_tower():
	game.get_node("HUD/Towers/PuffButton").pressed.emit()
	assert_eq(game.building, "puff")
	assert_true(game.place_at(5, 2))
	assert_eq(game.battle.towers[Vector2i(5, 2)].id, "puff")
	assert_eq(game.get_node("HUD/GoldLabel").text, "Sap: 50")


func test_a_built_tower_can_be_selected_and_sold():
	game.place_at(5, 2)
	assert_false(game.place_at(5, 2), "a second click selects it")
	assert_eq(game.selected, Vector2i(5, 2))
	assert_false(game.get_node("HUD/SellButton").disabled)
	game.get_node("HUD/SellButton").pressed.emit()
	assert_false(game.battle.towers.has(Vector2i(5, 2)))
	assert_gt(game.gold, 120 - 50)


func test_next_wave_starts_the_wave_at_once():
	game.get_node("HUD/NextWaveButton").pressed.emit()
	assert_eq(game.wave, 1)
	assert_eq(game.phase, "Wave")
	await wait_physics_frames(3)
	assert_eq(game.get_node("HUD/WaveLabel").text, "Wave 1 / 4")


func test_a_lost_map_shows_the_result_panel():
	game.battle.lives = 1
	game.speed = 8
	game.next_wave()
	for i in 1200:
		await wait_physics_frames(1)
		if game.state == "over":
			break
	assert_eq(game.state, "over")
	assert_eq(game.battle.phase, Battle.Phase.LOST)
	assert_true(game.get_node("ResultMenu").visible)
	assert_false(game.get_node("ResultMenu/Box/NextButton").visible)
