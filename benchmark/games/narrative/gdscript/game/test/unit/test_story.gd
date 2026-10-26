extends GutTest
## Story: one playthrough of the game's story, without a scene.

var graph := StoryGraph.from_files()


func test_a_story_begins_at_the_dock_with_every_flag_at_zero():
	var story := Story.new(graph)
	assert_eq(story.node_id, "dock")
	for flag: String in graph.flags:
		assert_eq(story.flags[flag], 0, flag)
	assert_eq(story.history.size(), 0)


func test_the_dock_offers_its_two_choices_in_order():
	var ids := []
	for choice: Dictionary in Story.new(graph).available():
		ids.append(choice.id)
	assert_eq(ids, ["dock_greet", "dock_silent"])


func test_a_choice_moves_the_story_and_is_remembered():
	var story := Story.new(graph)
	assert_true(story.choose("dock_silent"))
	assert_eq(story.node_id, "toll")
	assert_eq(story.history, PackedStringArray(["dock_silent"]))


func test_three_kind_words_give_three_trust():
	var story := Story.replay(graph, ["dock_greet", "toll_true", "launch_row", "fog_steady", "ask_name"])
	assert_eq(story.node_id, "name")
	assert_eq(story.flags.trust, 3)


func test_a_lie_is_set_and_a_confession_clears_it():
	var story := Story.replay(graph, ["dock_silent", "toll_lie", "launch_row", "fog_hurry"])
	assert_eq(story.flags.lied, 1)
	assert_true(story.choose("confess"))
	assert_eq(story.flags.lied, 0)


func test_a_confession_is_offered_only_after_a_lie():
	var honest := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry"])
	assert_eq(honest.node_id, "crossing")
	assert_false(honest.can_choose("confess"))
	var liar := Story.replay(graph, ["dock_silent", "toll_lie", "launch_row", "fog_hurry"])
	assert_true(liar.can_choose("confess"))


func test_a_choice_not_offered_is_refused_and_changes_nothing():
	var story := Story.new(graph)
	assert_false(story.choose("land"))
	assert_false(story.choose("no_such_choice"))
	assert_eq(story.node_id, "dock")
	assert_eq(story.history.size(), 0)


func test_an_ending_offers_nothing():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on", "turn_back"])
	assert_true(story.is_over())
	assert_eq(story.ending(), "return")
	assert_eq(story.available(), [])


func test_signals_tell_the_flags_and_the_ending():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"])
	watch_signals(story)
	assert_true(story.choose("turn_back"))
	assert_signal_emitted_with_parameters(story, "node_entered", ["end_return"])
	assert_signal_emitted_with_parameters(story, "ended", ["return"])
