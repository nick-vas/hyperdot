extends GutTest
## Hidden check for the alpha's migrate-save: settings files of version 1 ({"volume_db", "language"}, with or without
## "version": 1) load with their volume and language, and version 2 files still load as they are.

const PATH := "user://hidden_settings.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_version_1_decibels_become_a_linear_volume():
	_write_raw('{"version": 1, "volume_db": -6.0, "language": "fr"}')
	var data := SettingsStore.new(PATH).read()
	assert_almost_eq(float(data.volume), 0.501, 0.002)
	assert_eq(data.locale, "fr")
	assert_eq(int(data.version), 2)


func test_hidden_a_file_without_a_version_is_version_1():
	_write_raw('{"volume_db": -12.0, "language": "de"}')
	var data := SettingsStore.new(PATH).read()
	assert_almost_eq(float(data.volume), 0.251, 0.002)
	assert_eq(data.locale, "de")


func test_hidden_full_volume_stays_full():
	_write_raw('{"volume_db": 0.0, "language": "en"}')
	assert_almost_eq(float(SettingsStore.new(PATH).read().volume), 1.0, 0.001)


func test_hidden_a_migrated_file_is_written_as_version_2():
	_write_raw('{"volume_db": -6.0, "language": "fr"}')
	var store := SettingsStore.new(PATH)
	var data := store.read()
	data.played = 2
	store.write(data)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	var back := store.read()
	assert_almost_eq(float(back.volume), 0.501, 0.002)
	assert_eq(back.locale, "fr")
	assert_eq(int(back.played), 2)


func test_hidden_version_2_files_load_unchanged():
	_write_raw('{"version": 2, "volume": 0.3, "locale": "fr", "played": 4, "won": 1}')
	var data := SettingsStore.new(PATH).read()
	assert_almost_eq(float(data.volume), 0.3, 0.0001)
	assert_eq(data.locale, "fr")
	assert_eq(int(data.played), 4)
	assert_eq(int(data.won), 1)
