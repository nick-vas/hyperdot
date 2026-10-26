extends GutTest
## Hidden check for the alpha's fix-architecture: the sap line still follows a placement, a fallen pest, a sale and a
## new map.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_map(1, 7)
	await wait_physics_frames(2)


func _label() -> String:
	return game.get_node("HUD/GoldLabel").text


func test_hidden_a_placement_shows():
	game.place_at(3, 3)
	await wait_physics_frames(2)
	assert_eq(_label(), "Sap: 70")


func test_hidden_a_fallen_pest_shows():
	game.place_at(3, 3)
	var pest: Enemy = game.battle.spawn_at("aphid", Vector2i(3, 4))
	pest.speed = 0.0
	pest.hp = 1
	for i in 60:
		await wait_physics_frames(1)
		if not pest.alive:
			break
	await wait_physics_frames(2)
	assert_false(pest.alive)
	assert_eq(_label(), "Sap: %d" % (70 + int(game.catalog.enemies["aphid"].reward)))


func test_hidden_a_sale_and_a_new_map_show():
	game.place_at(3, 3)
	game.place_at(3, 3)
	game.sell_selected()
	await wait_physics_frames(2)
	assert_eq(_label(), "Sap: %d" % game.battle.gold)
	assert_gt(game.battle.gold, 70)
	game.start_map(2, 3)
	await wait_physics_frames(2)
	assert_eq(_label(), "Sap: %d" % int(game.catalog.map_at(2).gold))
