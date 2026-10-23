extends GutTest
## SaveStore: reading, writing, the run kept for Continue, and the move from version 1.

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
	assert_eq(int(data.meta.embers), 0)
	assert_null(data.run)
	assert_eq(str(data.settings.locale), "en")


func test_what_is_written_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	Meta.bank(data, 12, 3, true)
	assert_true(Meta.buy_vigor(data))
	data.settings.locale = "fr"
	assert_true(store.write(data))
	var back := store.read()
	assert_eq(int(back.meta.embers), 7)
	assert_eq(int(back.meta.vigor), 1)
	assert_eq(int(back.meta.best_floor), 3)
	assert_eq(int(back.meta.runs), 1)
	assert_eq(str(back.settings.locale), "fr")


func test_the_run_in_progress_reads_back():
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	var run := Run.new(42, 6)
	run.floor_number = 3
	run.hp = 4
	run.embers = 9
	data.run = run.to_dict()
	store.write(data)
	var back := Run.from_dict(store.read().run)
	assert_eq(back.seed_value, 42)
	assert_eq(back.floor_number, 3)
	assert_eq(back.hp, 4)
	assert_eq(back.max_hp, 6)
	assert_eq(back.embers, 9)
	assert_eq(back.floor_seed(), run.floor_seed())


func test_a_version_1_save_keeps_its_embers_and_deepest_floor():
	_write_raw('{"version": 1, "embers": 23, "best": 3}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.meta.embers), 23)
	assert_eq(int(data.meta.best_floor), 3)
	assert_eq(int(data.meta.vigor), 0)
	assert_null(data.run)


func test_a_disabled_store_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))


func test_a_damaged_file_gives_the_defaults():
	_write_raw("not json {")
	assert_eq(int(SaveStore.new(PATH).read().meta.embers), 0)
