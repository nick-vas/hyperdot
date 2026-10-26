extends GutTest
## Once-only choices: the questions at the crossing are asked once per story.

var graph := StoryGraph.from_files()


func _at_crossing() -> Story:
	return Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry"])


func test_a_question_asked_is_not_offered_again():
	var story := _at_crossing()
	assert_true(story.can_choose("ask_name"))
	assert_true(story.choose("ask_name"))
	assert_true(story.choose("name_back"))
	assert_eq(story.node_id, "crossing")
	assert_false(story.can_choose("ask_name"))
	assert_true(story.can_choose("ask_cargo"), "the other questions stay")


func test_trust_cannot_be_won_by_asking_twice():
	var story := _at_crossing()
	story.choose("ask_name")
	story.choose("name_back")
	assert_false(story.choose("ask_name"))
	assert_eq(story.flags.trust, 2)


func test_a_new_story_asks_again():
	var story := _at_crossing()
	story.choose("ask_name")
	assert_true(_at_crossing().can_choose("ask_name"))


func test_a_story_carried_on_remembers_what_was_asked():
	var story := _at_crossing()
	story.choose("ask_name")
	story.choose("name_back")
	var back := Story.from_dict(graph, story.to_dict())
	assert_false(back.can_choose("ask_name"))
