extends GutTest
## The rules of Story on a small story of its own: needs, the three effects, the history, moving on, and choices that
## are not offered.

var graph: StoryGraph


func before_each():
	graph = StoryGraph.from_data(
		[{"id": "a"}, {"id": "b"}, {"id": "c"}, {"id": "end"}],
		[
			{"id": "kind", "from": "a", "to": "b", "raise": ["trust"]},
			{"id": "scare", "from": "a", "to": "b", "set": ["afraid"]},
			{"id": "calm", "from": "b", "to": "c", "clear": ["afraid"]},
			{"id": "again", "from": "b", "to": "a"},
			{"id": "rush", "from": "b", "to": "c"},
			{"id": "trusted", "from": "c", "to": "end", "needs": "trust>=2;!afraid"},
			{"id": "back", "from": "c", "to": "a"},
		],
		[{"id": "trust", "kind": "count"}, {"id": "afraid", "kind": "switch"}],
		[{"id": "only", "node": "end"}])


func _ids(story: Story) -> Array:
	var out := []
	for choice: Dictionary in story.available():
		out.append(choice.id)
	return out


func test_raise_adds_one_each_time():
	var story := Story.replay(graph, ["kind", "again", "kind"])
	assert_eq(story.flags.trust, 2)


func test_set_makes_a_flag_one_and_clear_makes_it_zero():
	var story := Story.replay(graph, ["scare"])
	assert_eq(story.flags.afraid, 1)
	assert_true(story.choose("calm"))
	assert_eq(story.flags.afraid, 0)


func test_a_choice_is_offered_only_when_every_need_holds():
	var low := Story.replay(graph, ["kind", "calm"])
	assert_eq(_ids(low), ["back"], "trust 1 is not enough")
	var afraid := Story.replay(graph, ["kind", "again", "kind", "again", "scare", "rush"])
	assert_eq(afraid.node_id, "c")
	assert_eq(_ids(afraid), ["back"], "trust 2 but afraid")
	var trusted := Story.replay(graph, ["kind", "again", "kind", "calm"])
	assert_eq(_ids(trusted), ["trusted", "back"])


func test_a_choice_taken_moves_the_story_and_joins_the_history():
	var story := Story.new(graph)
	assert_true(story.choose("kind"))
	assert_eq(story.node_id, "b")
	assert_true(story.choose("calm"))
	assert_eq(story.node_id, "c")
	assert_eq(story.history, PackedStringArray(["kind", "calm"]))


func test_a_choice_not_offered_cannot_be_taken():
	var story := Story.new(graph)
	assert_false(story.choose("trusted"), "not out of this node")
	story = Story.replay(graph, ["kind", "calm"])
	assert_false(story.choose("trusted"), "its needs do not hold")
	assert_eq(story.node_id, "c")
	assert_eq(story.flags.trust, 1)
	assert_eq(story.history, PackedStringArray(["kind", "calm"]))


func test_an_ending_is_reached_and_offers_nothing():
	var story := Story.replay(graph, ["kind", "again", "kind", "calm", "trusted"])
	assert_eq(story.node_id, "end")
	assert_true(story.is_over())
	assert_eq(story.ending(), "only")
	assert_eq(_ids(story), [])
