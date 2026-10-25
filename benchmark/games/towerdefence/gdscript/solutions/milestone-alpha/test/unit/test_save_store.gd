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
	assert_eq(data.progress.size(), 0)
	assert_eq(str(data.settings.locale), "en")


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	Progress.record(data, "meadow", 20, 20)
	data.settings.locale = "fr"
	data.settings.volume = 0.25
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(Progress.stars(back, "meadow"), 3)
	assert_eq(str(back.settings.locale), "fr")
	assert_almost_eq(float(back.settings.volume), 0.25, 0.001)


func test_a_damaged_save_gives_the_defaults():
	_write_raw("{ not json")
	var data := SaveStore.new(PATH).read()
	assert_eq(data.progress.size(), 0)


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))
