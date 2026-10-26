extends GutTest
## Hidden check for the alpha's fix-architecture: the wick's hp on the HUD follows a hurt, a new floor and a new run.

var game: Node2D


func before_each():
	game = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.start_run(7)
	await wait_physics_frames(2)


func test_hidden_the_label_follows_a_hurt():
	var label: Label = game.get_node("HUD/HpLabel")
	assert_eq(label.text, "Wick: 5 / 5")
	game.world.hurt_wick(2)
	await wait_physics_frames(2)
	assert_eq(label.text, "Wick: 3 / 5")


func test_hidden_the_label_follows_a_new_floor_and_a_new_run():
	var label: Label = game.get_node("HUD/HpLabel")
	game.run.hp = 2
	game.start_floor(2)
	await wait_physics_frames(2)
	assert_eq(label.text, "Wick: 2 / 5")
	game.start_run(8)
	await wait_physics_frames(2)
	assert_eq(label.text, "Wick: 5 / 5")
