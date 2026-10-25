extends GutTest
## Hidden check for the beta's fix-playthrough: every ending can be reached again, and the shore still asks for trust
## and a calm ferrywoman, while the fog still frightens.

var graph := StoryGraph.from_files()


func _at_far_bank(trust: int, afraid: int) -> Story:
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"])
	assert_eq(story.node_id, "far_bank")
	story.flags.trust = trust
	story.flags.afraid = afraid
	return story


func test_hidden_every_ending_can_be_reached():
	var found := StoryCheck.search(graph)
	for id in ["shore", "return", "bell"]:
		assert_true(found.endings.has(id), id)
	assert_eq(StoryCheck.problems(graph), PackedStringArray())


func test_hidden_the_fog_still_frightens():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row"])
	assert_eq(story.node_id, "fog")
	assert_eq(int(story.flags.afraid), 1)


func test_hidden_steadying_yourself_calms_the_fear():
	var story := Story.replay(graph, ["dock_greet", "toll_true", "launch_row", "fog_steady"])
	assert_eq(story.node_id, "crossing")
	assert_eq(int(story.flags.afraid), 0)
	assert_true(story.choose("cross_on"))
	assert_true(story.can_choose("land"))


func test_hidden_the_shore_still_asks_for_trust_and_calm():
	assert_false(_at_far_bank(3, 1).can_choose("land"), "afraid")
	assert_false(_at_far_bank(1, 0).can_choose("land"), "not trusted enough")
	assert_true(_at_far_bank(2, 0).can_choose("land"))
