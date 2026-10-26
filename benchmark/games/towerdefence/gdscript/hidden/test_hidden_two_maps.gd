extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: two maps of four waves, and the save of each map's best.

const PATH := "user://test_hidden_two_maps.json"

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_two_maps_of_four_waves():
	assert_gte(catalog.map_count(), 2)
	assert_eq(catalog.map_at(1).id, "meadow")
	assert_eq(catalog.map_at(2).id, "sunken")
	assert_eq(catalog.waves_for("meadow").size(), 4)
	assert_eq(catalog.waves_for("sunken").size(), 4)
	assert_false(PathMap.from_rows(catalog.map_at(2).rows).route.is_empty())


func test_hidden_stars_are_saved_and_open_the_next_map():
	var store := SaveStore.new(PATH)
	var save := store.read()
	assert_false(Progress.is_unlocked(save, catalog, 2))
	Progress.record(save, "meadow", 20, 20)
	assert_true(store.write(save))
	var back := store.read()
	assert_eq(Progress.stars(back, "meadow"), 3)
	assert_true(Progress.is_unlocked(back, catalog, 2))
	Progress.record(back, "meadow", 9, 20)
	assert_eq(Progress.stars(back, "meadow"), 3, "the best result is kept")
	Progress.record(back, "sunken", 10, 20)
	assert_eq(Progress.stars(back, "sunken"), 2)
	Progress.record(back, "sunken", 9, 20)
	assert_eq(Progress.stars(back, "sunken"), 2)
