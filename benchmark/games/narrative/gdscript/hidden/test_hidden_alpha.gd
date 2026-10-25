extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: the story saved with its flags and history, once-only
## questions, and a story check that is clean for the game and finds a broken story.

const PATH := "user://test_hidden_alpha.json"

var graph := StoryGraph.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_a_story_comes_back_through_the_save():
	var story := Story.replay(graph, ["dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name"])
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.story = story.to_dict()
	data.endings = ["return"]
	assert_true(store.write(data))
	var read := store.read()
	assert_eq(Array(read.endings), ["return"])
	var back := Story.from_dict(graph, read.story)
	assert_eq(back.node_id, "name")
	assert_eq(int(back.flags.trust), 2)
	assert_eq(int(back.flags.lied), 1)
	assert_eq(back.history, story.history)


func test_hidden_the_questions_are_asked_once():
	var story := Story.replay(graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "ask_name", "name_back", "ask_cargo", "cargo_back"])
	assert_eq(story.node_id, "crossing")
	assert_false(story.can_choose("ask_name"))
	assert_false(story.can_choose("ask_cargo"))
	assert_true(story.can_choose("cross_on"))


func test_hidden_the_story_check_is_clean_for_the_game():
	assert_eq(StoryCheck.problems(graph), PackedStringArray())


func test_hidden_the_story_check_finds_a_broken_story():
	var broken := StoryGraph.from_data(
		[{"id": "a"}, {"id": "lost"}, {"id": "end"}],
		[{"id": "go", "from": "a", "to": "nowhere"}, {"id": "on", "from": "a", "to": "end", "set": ["kept"]},
		{"id": "out", "from": "lost", "to": "end"}],
		[{"id": "kept", "kind": "switch"}],
		[{"id": "end", "node": "end"}])
	var text := "\n".join(StoryCheck.problems(broken))
	for word in ["nowhere", "lost", "kept"]:
		assert_string_contains(text, word)
