extends GutTest
## Hidden check for the beta's fix-bug: recording a cleared map keeps every other map's result, and a worse replay keeps
## the best one.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_clearing_a_map_keeps_the_others():
	var save := SaveStore.defaults()
	Progress.record(save, "meadow", 20, 20)
	Progress.record(save, "sunken", 12, 20)
	Progress.record(save, "briar", 3, 20)
	assert_eq(Progress.stars(save, "meadow"), 3)
	assert_eq(Progress.stars(save, "sunken"), 2)
	assert_eq(Progress.stars(save, "briar"), 1)
	assert_true(Progress.is_unlocked(save, catalog, 2))
	assert_true(Progress.is_unlocked(save, catalog, 3))
	assert_eq(Progress.total_stars(save), 6)


func test_hidden_a_worse_replay_keeps_the_best():
	var save := SaveStore.defaults()
	Progress.record(save, "meadow", 20, 20)
	Progress.record(save, "sunken", 15, 20)
	Progress.record(save, "meadow", 4, 20)
	assert_eq(Progress.stars(save, "meadow"), 3)
	assert_eq(int(save.progress.meadow.lives), 20)
	Progress.record(save, "sunken", 18, 20)
	assert_eq(int(save.progress.sunken.lives), 18, "more seeds kept at the same stars is better")


func test_hidden_the_save_keeps_them_all():
	const PATH := "user://test_hidden_progress.json"
	var store := SaveStore.new(PATH)
	var save := store.read()
	Progress.record(save, "meadow", 20, 20)
	store.write(save)
	save = store.read()
	Progress.record(save, "sunken", 10, 20)
	store.write(save)
	var back := store.read()
	DirAccess.remove_absolute(PATH)
	assert_true(Progress.is_cleared(back, "meadow"))
	assert_true(Progress.is_cleared(back, "sunken"))
