extends GutTest
## Hidden check for the alpha's add-content: the drowned bell, a third ending reached only by those who asked about it.

var graph := StoryGraph.from_files()


func _offered(story: Story) -> Array:
	var out := []
	for choice: Dictionary in story.available():
		out.append(choice.id)
	return out


func test_hidden_the_bell_is_an_ending_of_its_own():
	assert_has(Array(graph.ending_ids), "bell")
	assert_eq(str(graph.endings.get("bell", {}).get("node", "")), "end_bell")
	assert_eq(str(graph.endings.get("bell", {}).get("title", "")), "ENDING_BELL")
	assert_eq(graph.ending_at("end_bell"), "bell")
	for id in ["shore", "return"]:
		assert_has(Array(graph.ending_ids), id)


func test_hidden_the_way_to_the_bell():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry"])
	assert_true(story.can_choose("ask_bell"), "the question is offered at the crossing")
	assert_true(story.choose("ask_bell"))
	assert_eq(story.node_id, "bell_tale")
	assert_eq(story.flags.get("knows_bell", 0), 1)
	assert_eq(_offered(story).size(), 1, "one way on from her tale")
	assert_true(story.choose(_offered(story)[0]))
	assert_eq(story.node_id, "crossing")
	assert_false(story.can_choose("ask_bell"), "asked once")
	assert_true(story.choose("cross_on"))
	assert_true(story.choose("to_tower"))
	assert_eq(story.node_id, "bell_tower")
	assert_eq(_offered(story).size(), 2, "ring the bell, or row back")
	assert_true(story.choose("ring_bell"))
	assert_eq(story.ending(), "bell")


func test_hidden_only_those_who_asked_find_the_tower():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"])
	assert_eq(story.node_id, "far_bank")
	assert_false(story.can_choose("to_tower"))
	var back := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_bell"])
	back.choose(_offered(back)[0])
	back.choose("cross_on")
	back.choose("to_tower")
	var row_back := ""
	for id in _offered(back):
		if id != "ring_bell":
			row_back = id
	assert_true(back.choose(row_back))
	assert_eq(back.node_id, "far_bank")


func test_hidden_the_story_check_passes_and_every_ending_is_reached():
	assert_eq(StoryCheck.problems(graph), PackedStringArray())
	var found := StoryCheck.search(graph)
	for id in ["shore", "return", "bell"]:
		assert_true(found.endings.has(id), id)


func test_hidden_the_new_text_is_written():
	for key in ["ENDING_BELL", graph.node("bell_tale").get("text", "?"), graph.node("bell_tower").get("text", "?"),
			graph.node("end_bell").get("text", "?"), graph.choice("ask_bell").get("text", "?"),
			graph.choice("to_tower").get("text", "?"), graph.choice("ring_bell").get("text", "?")]:
		assert_ne(TranslationServer.translate(key), key, key)
