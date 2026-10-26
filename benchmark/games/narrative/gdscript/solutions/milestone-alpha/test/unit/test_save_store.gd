extends GutTest
## SaveStore: reading and writing.

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


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))


func test_a_damaged_file_gives_the_defaults():
	_write_raw("not json {")
	assert_null(SaveStore.new(PATH).read().story)
