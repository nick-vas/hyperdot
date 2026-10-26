extends GutTest
## Hidden check for the alpha's migrate-save: a version 1 save (embers and the deepest floor) and one without a version
## load into the current shape, a run banked over a migrated save adds to it, and a version 2 save still loads as written.

const PATH := "user://test_hidden_migration.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_hidden_version_1_keeps_its_embers_and_floor():
	_write_raw('{"version": 1, "embers": 23, "best": 3}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.version), SaveStore.VERSION)
	assert_eq(int(data.meta.embers), 23)
	assert_eq(int(data.meta.best_floor), 3)
	assert_eq(int(data.meta.vigor), 0)
	assert_eq(int(data.meta.runs), 0)
	assert_null(data.run)
	assert_eq(str(data.settings.locale), "en")


func test_hidden_a_save_without_a_version_is_version_1():
	_write_raw('{"embers": 9, "best": 2}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.meta.embers), 9)
	assert_eq(int(data.meta.best_floor), 2)


func test_hidden_a_migrated_save_banks_and_writes_as_version_2():
	_write_raw('{"version": 1, "embers": 12, "best": 2}')
	var store := SaveStore.new(PATH)
	var data := store.read()
	assert_true(Meta.buy_vigor(data))
	Meta.bank(data, 4, 1, true)
	store.write(data)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 2)
	var back := store.read()
	assert_eq(int(back.meta.embers), 11)
	assert_eq(int(back.meta.vigor), 1)
	assert_eq(int(back.meta.best_floor), 2)


func test_hidden_version_2_still_loads():
	_write_raw('{"version": 2, "meta": {"embers": 30, "vigor": 2, "best_floor": 4, "runs": 7}, "run": {"seed": 5, "floor": 2, "hp": 3, "max_hp": 7, "embers": 4}, "settings": {"volume": 0.5, "locale": "en"}}')
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.meta.embers), 30)
	assert_eq(int(data.meta.vigor), 2)
	assert_eq(int(data.meta.best_floor), 4)
	assert_eq(int(data.meta.runs), 7)
	assert_eq(int(data.run.floor), 2)
	assert_almost_eq(float(data.settings.volume), 0.5, 0.001)
