extends GutTest
## Hidden check for the alpha's fix-architecture: the chapter label follows the story, set by the story itself.

var scene: Control


func before_each():
	scene = load("res://story/story.tscn").instantiate()
	add_child_autofree(scene)
	await wait_physics_frames(2)


func _label() -> String:
	return scene.get_node("HUD/ChapterLabel").text


func test_hidden_the_label_shows_the_first_chapter():
	assert_eq(_label(), "Chapter 1: The Landing")


func test_hidden_the_label_follows_the_story_into_the_fog():
	scene.resume(Story.replay(scene.graph, ["dock_silent", "toll_true"]).to_dict())
	scene.reveal_all()
	await wait_physics_frames(3)
	assert_eq(_label(), "Chapter 1: The Landing")
	assert_true(scene.choose_id("launch_row"))
	await wait_physics_frames(scene.TURN_TICKS + 1)
	assert_eq(scene.node, "fog")
	assert_eq(_label(), "Chapter 2: The Crossing")


func test_hidden_the_label_follows_a_story_carried_on_and_a_new_one():
	scene.resume(Story.replay(scene.graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"]).to_dict())
	await wait_physics_frames(1)
	assert_eq(_label(), "Chapter 3: The Far Bank")
	scene.start_new()
	await wait_physics_frames(1)
	assert_eq(_label(), "Chapter 1: The Landing")
