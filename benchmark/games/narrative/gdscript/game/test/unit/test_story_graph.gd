extends GutTest
## StoryGraph: the story's tables as the game reads them.

var graph := StoryGraph.from_files()


func test_the_story_starts_at_the_first_node():
	assert_eq(graph.start, "dock")
	assert_eq(graph.node("dock").speaker, "narrator")
	assert_eq(graph.node("dock").chapter, 1)


func test_choices_out_of_a_node_come_in_file_order():
	var ids := []
	for choice: Dictionary in graph.choices_from("toll"):
		ids.append(choice.id)
	assert_eq(ids, ["toll_true", "toll_lie"])
	assert_eq(graph.choice("toll_lie").set, PackedStringArray(["lied"]))


func test_each_ending_is_a_node_of_the_story():
	assert_gt(graph.ending_ids.size(), 1, "more than one ending")
	for id in graph.ending_ids:
		var at: String = graph.endings[id].node
		assert_true(graph.has_node(at), at)
		assert_eq(graph.ending_at(at), id)
	assert_eq(graph.ending_at("dock"), "")
