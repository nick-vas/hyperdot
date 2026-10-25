extends GutTest
## Hidden check for the alpha's migrate-save: a version 2 save, with the embers and dawns beside the economy, keeps them
## (and everything else) when it loads, a file without a version is read the same way, and version 3 files are
## untouched.

const PATH := "user://test_hidden_save_migration.json"
const V2 := '{"version": 2, "economy": {"glow": 123456789012345678901.0, "run_earned": 2e21, "total_earned": 5e21, "owned": {"wick_moth": 40, "moon_lily": 3}, "upgrades": ["twin_wicks"]}, "embers": 37.0, "dawns": 5, "saved_at": 1760000000.0, "settings": {"volume": 0.4, "locale": "en"}}'


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _write_raw(text: String) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _load(text: String) -> Dictionary:
	_write_raw(text)
	return SaveStore.new(PATH).read()


func test_hidden_version_2_keeps_its_embers_and_dawns():
	var data := _load(V2)
	assert_eq(int(data.version), 3)
	var economy := Economy.from_dict(Catalog.from_files(), data.economy)
	assert_eq(economy.embers, 37.0)
	assert_eq(economy.dawns, 5)
	assert_almost_eq(economy.ember_multiplier(), 4.7, 1e-9)


func test_hidden_version_2_keeps_everything_else():
	var data := _load(V2)
	var economy := Economy.from_dict(Catalog.from_files(), data.economy)
	assert_eq(economy.glow, 123456789012345678901.0)
	assert_eq(economy.total_earned, 5e21)
	assert_eq(economy.count("wick_moth"), 40)
	assert_eq(economy.count("moon_lily"), 3)
	assert_true(economy.upgrades.has("twin_wicks"))
	assert_eq(data.saved_at, 1760000000.0)
	assert_almost_eq(float(data.settings.volume), 0.4, 1e-9)


func test_hidden_a_file_without_a_version_is_version_2():
	var data := _load('{"economy": {"glow": 5.0}, "embers": 2.0, "dawns": 1}')
	var economy := Economy.from_dict(Catalog.from_files(), data.economy)
	assert_eq(economy.embers, 2.0)
	assert_eq(economy.glow, 5.0)


func test_hidden_a_migrated_save_is_written_as_version_3():
	var store := SaveStore.new(PATH)
	var data := _load(V2)
	assert_true(store.write(data))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_eq(int(raw.version), 3)
	assert_eq(float(raw.economy.prestige.embers), 37.0)
	var again := Economy.from_dict(Catalog.from_files(), store.read().economy)
	assert_eq(again.embers, 37.0)
	assert_eq(again.dawns, 5)


func test_hidden_version_3_is_untouched():
	var economy := Economy.new(Catalog.from_files())
	economy.embers = 12.0
	economy.dawns = 3
	economy.glow = 77.0
	SaveStore.new(PATH).write({"economy": economy.to_dict(), "saved_at": 1.0, "settings": {"volume": 1.0, "locale": "en"}})
	var back := Economy.from_dict(economy.catalog, SaveStore.new(PATH).read().economy)
	assert_eq(back.embers, 12.0)
	assert_eq(back.dawns, 3)
	assert_eq(back.glow, 77.0)
