extends GutTest
## SaveStore: reading, writing, best laps and their ghosts.

const PATH := "user://test_save.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_no_save_gives_the_defaults():
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), SaveStore.VERSION)
	assert_eq(int(data.unlocked), 1)
	assert_eq(data.best, {})


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	data.unlocked = 3
	data.best["1"] = 25480
	data.settings.locale = "fr"
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(int(back.unlocked), 3)
	assert_eq(int(back.best["1"]), 25480)
	assert_eq(back.settings.locale, "fr")


func test_a_damaged_save_gives_the_defaults():
	_write_raw("{ not json")
	assert_eq(int(SaveStore.new(PATH).read().unlocked), 1)


func test_a_lap_is_kept_only_when_it_beats_the_best():
	var data := SaveStore.defaults()
	var ghost := Ghost.new({"position": Vector2.ZERO, "heading": 0.0, "speed": 0.0})
	ghost.record(1.0, 0.0)
	assert_true(SaveStore.record_lap(data, 2, 30000, ghost))
	assert_false(SaveStore.record_lap(data, 2, 31000, null))
	assert_true(SaveStore.record_lap(data, 2, 29500, ghost))
	assert_eq(int(data.best["2"]), 29500)
	assert_true(data.ghosts.has("2"))


func test_a_saved_ghost_comes_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	var ghost := Ghost.new({"position": Vector2(10.5, -3.25), "heading": 0.75, "speed": 120.0})
	for i in 10:
		ghost.record(1.0, -0.37)
	SaveStore.record_lap(data, 1, 9000, ghost)
	store.write(data)
	var back := Ghost.from_dict(store.read().ghosts.get("1"))
	assert_eq(back.ticks(), 10)
	assert_eq(back.start.position, Vector2(10.5, -3.25))
	assert_eq(back.input_at(9), Vector2(1.0, -0.37))


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))
