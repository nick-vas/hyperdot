extends GutTest
## Hidden check for the beta's fix-performance: the choices are worked out once per line, not every frame, and the
## buttons shown stay the same while the player thinks.

var scene: Control


func before_each():
	scene = load("res://story/story.tscn").instantiate()
	scene.setup(StoryGraph.from_files(), LaunchOptions.new(), [])
	add_child_autofree(scene)
	await wait_physics_frames(2)


func _until_choosing() -> void:
	for i in 300:
		if scene.state == "choosing":
			return
		await wait_physics_frames(1)


func test_hidden_an_idle_player_costs_no_work():
	await _until_choosing()
	var before: int = scene.choice_checks
	var button: Node = scene.get_node("Choices/Choice0")
	await wait_physics_frames(120)
	assert_lte(scene.choice_checks - before, 1, "worked out at most once more over 120 idle frames")
	assert_true(is_instance_valid(button) and button.is_inside_tree(), "the same button is still shown")
	assert_eq(scene.get_node("Choices").get_child_count(), 2)


func test_hidden_each_line_works_its_choices_out_once():
	await _until_choosing()
	var before: int = scene.choice_checks
	assert_true(scene.choose_id("dock_greet"))
	await _until_choosing()
	await wait_physics_frames(30)
	assert_eq(scene.node, "toll")
	assert_between(scene.choice_checks - before, 1, 2)
	assert_eq(scene.get_node("Choices/Choice1").text, "Three coppers. The river is high tonight.")
