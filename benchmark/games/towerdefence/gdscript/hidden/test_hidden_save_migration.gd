extends GutTest
## Hidden check for the alpha's migrate-save: version 1 saves (a list of maps cleared and the volume) load as cleared
## maps, a save without a version is version 1, recording over a migrated save works, and version 2 saves load as they
## were.

const PATH := "user://test_hidden_save_migration.json"

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_a_version_1_save_keeps_its_cleared_maps():
	_write_raw('{"version": 1, "cleared": ["meadow"], "volume": 0.4}')
	var data := SaveStore.new(PATH).read()
	assert_true(Progress.is_cleared(data, "meadow"))
	assert_false(Progress.is_cleared(data, "sunken"))
	assert_true(Progress.is_unlocked(data, catalog, 2))
	assert_almost_eq(float(data.settings.volume), 0.4, 0.001)
	assert_eq(str(data.settings.locale), "en")


func test_hidden_a_save_without_a_version_is_version_1():
	_write_raw('{"cleared": ["meadow", "sunken"]}')
	var data := SaveStore.new(PATH).read()
	assert_true(Progress.is_cleared(data, "meadow"))
	assert_true(Progress.is_cleared(data, "sunken"))


func test_hidden_a_migrated_save_records_and_writes_as_version_2():
	_write_raw('{"version": 1, "cleared": ["meadow"], "volume": 1.0}')
	var store := SaveStore.new(PATH)
	var data := store.read()
	Progress.record(data, "meadow", 20, 20)
	Progress.record(data, "sunken", 8, 20)
	assert_true(store.write(data))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	var back := store.read()
	assert_eq(Progress.stars(back, "meadow"), 3)
	assert_eq(Progress.stars(back, "sunken"), 1)


func test_hidden_a_version_2_save_loads_as_it_was():
	_write_raw('{"version": 2, "progress": {"sunken": {"stars": 2, "lives": 12}}, "settings": {"volume": 0.5, "locale": "en"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(Progress.stars(data, "sunken"), 2)
	assert_eq(int(data.progress.sunken.lives), 12)
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
