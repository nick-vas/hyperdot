extends GutTest
## A story kept in the save comes back where it was: the node, the switches set and cleared, and the history.

const PATH := "user://test_story_save.json"

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


func test_the_node_and_the_history_come_back():
	var story := Story.replay(graph, ["dock_silent", "toll_lie", "launch_row"])
	var back := _through_the_save(story)
	assert_eq(back.node_id, "fog")
	assert_eq(back.history, story.history)


func test_a_lie_told_before_the_save_can_still_be_confessed():
	var story := Story.replay(graph, ["dock_silent", "toll_lie", "launch_row", "fog_hurry"])
	var back := _through_the_save(story)
	assert_eq(back.flags.lied, 1)
	assert_eq(back.flags.afraid, 1)
	assert_true(back.can_choose("confess"))


func test_a_saved_node_the_story_lost_starts_over():
	var back := Story.from_dict(graph, {"node": "gone", "flags": {}, "history": []})
	assert_eq(back.node_id, "dock")
