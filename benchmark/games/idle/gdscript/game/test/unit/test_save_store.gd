extends GutTest
## SaveStore: reading, writing and the move from version 2.

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
	assert_eq(data.economy, {})


func test_a_damaged_file_gives_the_defaults():
	_write_raw("{ not json")
	assert_eq(SaveStore.new(PATH).read().economy, {})


func test_a_save_comes_back_as_written():
	var economy := Economy.new(Catalog.from_files())
	economy.glow = 12345678901234567890.0
	economy.owned["moon_lily"] = 7
	economy.upgrades["warm_hands"] = true
	economy.embers = 3.0
	economy.dawns = 2
	var store := SaveStore.new(PATH)
	assert_true(store.write({"economy": economy.to_dict(), "saved_at": 1761000000.5, "settings": {"volume": 0.5, "locale": "de"}}))
	var data := store.read()
	var back := Economy.from_dict(economy.catalog, data.economy)
	assert_eq(back.glow, economy.glow, "past 2^53, the same double")
	assert_eq(back.count("moon_lily"), 7)
	assert_true(back.upgrades.has("warm_hands"))
	assert_eq(back.embers, 3.0)
	assert_eq(back.dawns, 2)
	assert_eq(data.saved_at, 1761000000.5)
	assert_eq(data.settings.locale, "de")


func test_a_version_2_save_keeps_its_embers():
	_write_raw('{"version": 2, "economy": {"glow": 50.0, "owned": {"wick_moth": 3}}, "embers": 4.0, "dawns": 2, "saved_at": 100.0}')
	var back := Economy.from_dict(Catalog.from_files(), SaveStore.new(PATH).read().economy)
	assert_eq(back.embers, 4.0)
	assert_eq(back.dawns, 2)
	assert_eq(back.count("wick_moth"), 3)


func test_writing_off_writes_nothing():
	var store := SaveStore.new(PATH)
	store.enabled = false
	assert_false(store.write(SaveStore.defaults()))
	assert_false(FileAccess.file_exists(PATH))
