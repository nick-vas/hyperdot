extends GutTest
## Hidden check for the alpha's migrate-save: a version 1 save carries on its story and keeps its endings.

const PATH := "user://test_hidden_save_migration.json"

var graph := StoryGraph.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(text: String) -> Dictionary:
	_write_raw(text)
	return SaveStore.new(PATH).read()


func test_hidden_a_version_1_story_carries_on_where_it_was():
	var data := _read('{"version": 1, "choices": ["dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name"], "found": ["return", "shore"]}')
	assert_eq(int(data.version), SaveStore.VERSION)
	assert_eq(Array(data.endings), ["return", "shore"])
	assert_eq(typeof(data.story), TYPE_DICTIONARY, "a story to continue")
	var story := Story.from_dict(graph, data.story)
	var played := Story.replay(graph, ["dock_greet", "toll_lie", "launch_row", "fog_steady", "ask_name"])
	assert_eq(story.node_id, "name")
	assert_eq(int(story.flags.trust), 2)
	assert_eq(int(story.flags.lied), 1)
	assert_eq(int(story.flags.afraid), 0)
	assert_eq(story.history, played.history)
	assert_false(story.can_choose("ask_name"))
	assert_true(story.choose("name_back"))
	assert_true(story.can_choose("confess"))


func test_hidden_a_file_without_a_version_is_version_1():
	var data := _read('{"choices": ["dock_silent"], "found": ["return"]}')
	assert_eq(Array(data.endings), ["return"])
	assert_eq(Story.from_dict(graph, data.story).node_id, "toll")


func test_hidden_a_version_1_save_between_stories_has_nothing_to_continue():
	var data := _read('{"version": 1, "choices": [], "found": ["shore"]}')
	assert_eq(Array(data.endings), ["shore"])
	assert_null(data.story)


func test_hidden_a_migrated_save_is_written_as_the_current_version():
	var store := SaveStore.new(PATH)
	_write_raw('{"version": 1, "choices": ["dock_greet"], "found": ["return"]}')
	var data := store.read()
	SaveStore.record_ending(data, "shore")
	assert_true(store.write(data))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), SaveStore.VERSION)
	var back := store.read()
	assert_eq(Array(back.endings), ["return", "shore"])
	assert_eq(str(back.story.node), "toll")


func test_hidden_a_version_2_save_is_read_as_it_is():
	var data := _read('{"version": 2, "story": {"node": "fog", "flags": {"trust": 1, "lied": 0, "afraid": 1}, "history": ["dock_greet", "toll_lie", "launch_row"]}, "endings": ["shore"], "settings": {"volume": 0.5, "locale": "en"}}')
	assert_eq(Array(data.endings), ["shore"])
	assert_eq(str(data.story.node), "fog")
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
