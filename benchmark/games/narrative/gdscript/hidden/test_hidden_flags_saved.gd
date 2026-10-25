extends GutTest
## Hidden check for the alpha's fix-bug: a story kept in the save comes back with every flag at its value, so trust won
## and a lie told before quitting still count after Continue.

const PATH := "user://test_hidden_flags_saved.json"

var graph := StoryGraph.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _through_the_save(story: Story) -> Story:
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.story = story.to_dict()
	assert_true(store.write(data))
	return Story.from_dict(graph, store.read().story)


func test_hidden_every_flag_comes_back_at_its_value():
	var story := Story.replay(graph, ["dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name"])
	assert_eq(story.flags.trust, 2)
	var back := _through_the_save(story)
	for flag: String in graph.flags:
		assert_eq(int(back.flags.get(flag, -1)), int(story.flags[flag]), flag)


func test_hidden_trust_won_before_the_save_lets_the_boat_land():
	var story := Story.replay(graph, ["dock_greet", "toll_true", "launch_row", "fog_steady", "cross_on"])
	var back := _through_the_save(story)
	assert_eq(back.node_id, "far_bank")
	assert_true(back.can_choose("land"))
	assert_true(back.choose("land"))
	assert_eq(back.ending(), "shore")


func test_hidden_three_trust_stays_three():
	var story := Story.replay(graph, ["dock_greet", "toll_true", "launch_row", "fog_hurry", "ask_name"])
	assert_eq(story.flags.trust, 3)
	assert_eq(_through_the_save(story).flags.trust, 3)


func test_hidden_the_story_scene_carries_on_with_the_flags():
	var story := Story.replay(graph, ["dock_greet", "toll_lie", "launch_row", "fog_steady"])
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.story = story.to_dict()
	store.write(data)
	var scene: Control = load("res://story/story.tscn").instantiate()
	scene.setup(graph, LaunchOptions.new(), [], store.read().story)
	add_child_autofree(scene)
	await wait_physics_frames(2)
	assert_eq(scene.node, "crossing")
	assert_eq(int(scene.story.flags.trust), 1)
	assert_eq(int(scene.story.flags.lied), 1)
	assert_true(scene.story.can_choose("confess"))
