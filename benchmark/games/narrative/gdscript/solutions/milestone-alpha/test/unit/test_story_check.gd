extends GutTest
## StoryCheck on the game's story, and on small broken ones: what the data runner cannot see.

var graph := StoryGraph.from_files()


func _graph(nodes: Array, choices: Array, flags := [], endings := [{"id": "end", "node": "end"}]) -> StoryGraph:
	return StoryGraph.from_data(nodes, choices, flags, endings)


func test_the_story_has_no_problems():
	assert_eq(StoryCheck.problems(graph), PackedStringArray())


func test_every_ending_can_be_reached():
	var found := StoryCheck.search(graph)
	for id in graph.ending_ids:
		assert_true(found.endings.has(id), id)
	assert_eq(found.nodes.size(), graph.nodes.size())


func test_the_way_to_each_ending_is_offered_choice_by_choice():
	for id in graph.ending_ids:
		var path := StoryCheck.path_to(graph, id)
		var story := Story.new(graph)
		for choice in path:
			assert_true(story.choose(choice), "%s on the way to %s" % [choice, id])
		assert_eq(story.ending(), id)


func test_a_choice_to_a_missing_node_is_found():
	var broken := _graph([{"id": "a"}, {"id": "end"}], [{"id": "go", "from": "a", "to": "ned"}, {"id": "on", "from": "a", "to": "end"}])
	assert_has(StoryCheck.problems(broken), "choice 'go' leads to 'ned', which is no node")


func test_a_node_nobody_reaches_is_found():
	var broken := _graph([{"id": "a"}, {"id": "lost"}, {"id": "end"}], [{"id": "on", "from": "a", "to": "end"}, {"id": "out", "from": "lost", "to": "end"}])
	assert_has(StoryCheck.problems(broken), "node 'lost' cannot be reached")


func test_flags_set_and_never_read_or_read_and_never_set_are_found():
	var broken := _graph([{"id": "a"}, {"id": "end"}],
		[{"id": "on", "from": "a", "to": "end", "needs": "!ghost", "set": ["kept"]}],
		[{"id": "kept", "kind": "switch"}])
	var problems := StoryCheck.problems(broken)
	assert_has(problems, "flag 'kept' is never read")
	assert_has(problems, "flag 'ghost' of choice 'on' is not in flags.json")


func test_an_ending_a_flag_locks_away_is_found():
	var broken := _graph([{"id": "a"}, {"id": "b"}, {"id": "end"}, {"id": "other"}],
		[{"id": "scare", "from": "a", "to": "b", "set": ["afraid"]},
		{"id": "calm", "from": "b", "to": "b", "needs": "afraid=1"},
		{"id": "land", "from": "b", "to": "end", "needs": "!afraid"},
		{"id": "flee", "from": "b", "to": "other"}],
		[{"id": "afraid", "kind": "switch"}],
		[{"id": "end", "node": "end"}, {"id": "other", "node": "other"}])
	assert_has(StoryCheck.problems(broken), "ending 'end' cannot be reached")


func test_a_story_that_can_get_stuck_is_found():
	var broken := _graph([{"id": "a"}, {"id": "b"}, {"id": "end"}],
		[{"id": "lie", "from": "a", "to": "b", "set": ["lied"]}, {"id": "truth", "from": "a", "to": "b"},
		{"id": "on", "from": "b", "to": "end", "needs": "!lied"}],
		[{"id": "lied", "kind": "switch"}])
	var problems := "\n".join(StoryCheck.problems(broken))
	assert_string_contains(problems, "a story can get stuck at 'b'")
