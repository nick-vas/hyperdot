extends GutTest
## SettingsStore: reading and writing.

const PATH := "user://test_settings.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_no_file_gives_the_defaults():
	assert_eq(SettingsStore.new(PATH).read(), SettingsStore.defaults())


func test_settings_survive_a_write_and_a_read():
	var store := SettingsStore.new(PATH)
	var data := SettingsStore.defaults()
	data.volume = 0.4
	data.locale = "fr"
	data.played = 3
	data.won = 1
	assert_true(store.write(data))
	var back := store.read()
	assert_almost_eq(float(back.volume), 0.4, 0.0001)
	assert_eq(back.locale, "fr")
	assert_eq(back.played, 3)
	assert_eq(back.won, 1)


func test_a_damaged_file_gives_the_defaults():
	_write_raw("{ not json")
	assert_eq(SettingsStore.new(PATH).read(), SettingsStore.defaults())


func test_writing_is_off_with_no_save():
	var store := SettingsStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SettingsStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))
