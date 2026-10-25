extends GutTest
## Hidden check for the prototype's fix-bug: asking about the stranger's bag leads to her answer and on, every choice of
## the story leads to a node, and every node can be reached.

var graph := StoryGraph.from_files()


func _at_crossing() -> Story:
	return Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry"])


func test_hidden_asking_about_the_bag_leads_to_her_answer():
	var story := _at_crossing()
	assert_eq(story.node_id, "crossing")
	assert_true(story.can_choose("ask_cargo"), "the question is offered")
	assert_true(story.choose("ask_cargo"))
	assert_true(graph.has_node(story.node_id), "a node of the story")
	assert_eq(str(story.current().get("text", "")), "N_CARGO")


func test_hidden_her_answer_leads_back_to_the_crossing():
	var story := _at_crossing()
	story.choose("ask_cargo")
	var open := story.available()
	assert_eq(open.size(), 1)
	if open.size() == 1:
		assert_true(story.choose(open[0].id))
		assert_eq(story.node_id, "crossing")


func test_hidden_every_choice_leads_to_a_node():
	for id: String in graph.choices:
		assert_true(graph.has_node(graph.choices[id].to), "%s -> %s" % [id, graph.choices[id].to])


func test_hidden_every_node_can_be_reached():
	var seen := {graph.start: true}
	var queue := [graph.start]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for choice: Dictionary in graph.choices_from(at):
			if not seen.has(choice.to):
				seen[choice.to] = true
				queue.append(choice.to)
	for id: String in graph.nodes:
		assert_true(seen.has(id), id)
