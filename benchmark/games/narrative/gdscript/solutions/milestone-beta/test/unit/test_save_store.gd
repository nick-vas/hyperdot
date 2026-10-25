extends GutTest
## SaveStore: reading, writing and the move from version 1.

const PATH := "user://test_save_store.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_no_file_gives_the_defaults():
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), SaveStore.VERSION)
	assert_null(data.story)
	assert_eq(data.endings, [])
	assert_eq(str(data.settings.locale), "en")


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	SaveStore.record_ending(data, "return")
	SaveStore.record_ending(data, "return")
	data.story = {"node": "toll", "flags": {"trust": 1}, "history": ["dock_greet"]}
	data.settings.locale = "fr"
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(back.endings, ["return"])
	assert_eq(str(back.story.node), "toll")
	assert_eq(str(back.settings.locale), "fr")


func test_a_version_1_save_keeps_its_story_and_endings():
	_write_raw('{"version": 1, "choices": ["dock_greet", "toll_lie", "launch_row"], "found": ["return"]}')
	var data := SaveStore.new(PATH).read()
	assert_eq(data.endings, ["return"])
	var story := Story.from_dict(StoryGraph.from_files(), data.story)
	assert_eq(story.node_id, "fog")
	assert_eq(story.flags.trust, 1)
	assert_eq(story.flags.lied, 1)


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))


func test_a_damaged_file_gives_the_defaults():
	_write_raw("not json {")
	assert_null(SaveStore.new(PATH).read().story)
