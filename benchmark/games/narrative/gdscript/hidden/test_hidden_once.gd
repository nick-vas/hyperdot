extends GutTest
## Hidden check for the prototype's add-feature: once-only choices, on a story of its own and on the game's questions.

var graph := StoryGraph.from_files()


func _hub() -> StoryGraph:
	return StoryGraph.from_data(
		[{"id": "hub"}, {"id": "answer"}, {"id": "end"}],
		[
			{"id": "ask", "from": "hub", "to": "answer", "raise": ["asked"], "once": true},
			{"id": "look", "from": "hub", "to": "answer"},
			{"id": "leave", "from": "hub", "to": "end", "needs": "asked>=0"},
			{"id": "back", "from": "answer", "to": "hub"},
		],
		[{"id": "asked", "kind": "count"}],
		[{"id": "end", "node": "end"}])


func _ids(story: Story) -> Array:
	var out := []
	for choice: Dictionary in story.available():
		out.append(choice.id)
	return out


func test_hidden_the_graph_reads_once():
	var hub := _hub()
	assert_true(bool(hub.choice("ask").get("once", false)))
	assert_false(bool(hub.choice("look").get("once", false)))


func test_hidden_a_once_choice_is_offered_until_taken():
	var story := Story.new(_hub())
	assert_eq(_ids(story), ["ask", "look", "leave"])
	assert_true(story.choose("ask"))
	assert_true(story.choose("back"))
	assert_eq(_ids(story), ["look", "leave"])
	assert_false(story.choose("ask"))
	assert_eq(story.flags.asked, 1)


func test_hidden_other_choices_can_be_taken_again():
	var story := Story.new(_hub())
	for i in 3:
		assert_true(story.choose("look"))
		assert_true(story.choose("back"))
	assert_true(story.can_choose("ask"))


func test_hidden_a_new_story_offers_it_again():
	var hub := _hub()
	Story.replay(hub, ["ask", "back"])
	assert_true(Story.new(hub).can_choose("ask"))


func test_hidden_a_story_carried_on_remembers_it():
	var hub := _hub()
	var story := Story.replay(hub, ["ask", "back"])
	var back := Story.from_dict(hub, JSON.parse_string(JSON.stringify(story.to_dict())))
	assert_false(back.can_choose("ask"))
	assert_true(back.can_choose("look"))


func test_hidden_the_stranger_answers_each_question_once():
	assert_true(bool(graph.choice("ask_name").get("once", false)), "ask_name")
	assert_true(bool(graph.choice("ask_cargo").get("once", false)), "ask_cargo")
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_name", "name_back"])
	assert_false(story.can_choose("ask_name"))
	assert_true(story.can_choose("ask_cargo"))
	assert_true(story.can_choose("cross_on"))
	assert_eq(story.flags.trust, 2)
