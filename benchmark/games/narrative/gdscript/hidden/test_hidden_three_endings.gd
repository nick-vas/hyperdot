extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the drowned bell is the third ending, reached only by those who
## asked about it, and the story check is clean.

var graph := StoryGraph.from_files()


func test_hidden_three_endings_each_reached():
	assert_eq(Array(graph.ending_ids), ["shore", "return", "bell"])
	assert_eq(graph.ending_at("end_bell"), "bell")
	var found := StoryCheck.search(graph)
	for id in graph.ending_ids:
		assert_true(found.endings.has(id), id)
	assert_eq(StoryCheck.problems(graph), PackedStringArray())


func test_hidden_the_tower_needs_the_tale():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"])
	assert_false(story.can_choose("to_tower"))
	story = Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_bell"])
	assert_eq(story.node_id, "bell_tale")
	assert_eq(int(story.flags.get("knows_bell", 0)), 1)
	assert_true(story.choose(story.available()[0].id))
	assert_true(story.choose("cross_on"))
	assert_true(story.choose("to_tower"))
	assert_true(story.choose("ring_bell"))
	assert_eq(story.ending(), "bell")
