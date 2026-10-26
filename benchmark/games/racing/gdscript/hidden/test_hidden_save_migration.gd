extends GutTest
## Hidden check for the alpha's migrate-save: a version 1 save (best laps in seconds) loads with its laps in
## milliseconds and its tracks open, a file without a version is version 1, a version 2 save is as it was, and saving
## a migrated save writes version 2.

const PATH := "user://hidden_migration_save.json"


func after_each():
	for path in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_version_1_best_laps_come_back_in_milliseconds():
	_write_raw('{"version": 1, "best": {"1": 25.481, "2": 30.0}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), 2)
	assert_eq(int(data.best["1"]), 25481)
	assert_eq(int(data.best["2"]), 30000)


func test_hidden_version_1_tracks_stay_open():
	_write_raw('{"version": 1, "best": {"1": 25.5}}')
	assert_eq(int(SaveStore.new(PATH).read().unlocked), 2)
	_write_raw('{"version": 1, "best": {"1": 25.5, "2": 31.25}}')
	assert_gte(int(SaveStore.new(PATH).read().unlocked), 3)


func test_hidden_a_save_without_a_version_is_version_1():
	_write_raw('{"best": {"1": 26.0}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.best["1"]), 26000)
	assert_eq(int(data.unlocked), 2)


func test_hidden_a_version_2_save_is_as_it_was():
	_write_raw('{"version": 2, "unlocked": 2, "best": {"1": 25481}, "ghosts": {}, "settings": {"volume": 0.5, "locale": "en"}, "controls": {"brake": "K"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.unlocked), 2)
	assert_eq(int(data.best["1"]), 25481)
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
	assert_eq(data.controls.get("brake"), "K")


func test_hidden_a_migrated_save_is_written_as_version_2():
	_write_raw('{"version": 1, "best": {"2": 33.5}}')
	var store := SaveStore.new(PATH)
	store.write(store.read())
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	assert_eq(int(raw.best["2"]), 33500)
	assert_eq(int(SaveStore.new(PATH).read().best["2"]), 33500)
