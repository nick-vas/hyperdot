extends GutTest
## Progress: stars for a cleared map, the best result kept, and which maps are open.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_stars_follow_the_seeds_kept():
	assert_eq(Progress.stars_for(20, 20), 3)
	assert_eq(Progress.stars_for(10, 20), 2)
	assert_eq(Progress.stars_for(9, 20), 1)
	assert_eq(Progress.stars_for(1, 20), 1)


func test_a_cleared_map_opens_the_next():
	var save := SaveStore.defaults()
	assert_true(Progress.is_unlocked(save, catalog, 1))
	assert_false(Progress.is_unlocked(save, catalog, 2))
	Progress.record(save, "meadow", 12, 20)
	assert_true(Progress.is_cleared(save, "meadow"))
	assert_eq(Progress.stars(save, "meadow"), 2)
	assert_true(Progress.is_unlocked(save, catalog, 2))
	assert_false(Progress.is_unlocked(save, catalog, 3))


func test_a_better_replay_raises_the_stars():
	var save := SaveStore.defaults()
	Progress.record(save, "meadow", 5, 20)
	Progress.record(save, "meadow", 20, 20)
	assert_eq(Progress.stars(save, "meadow"), 3)
	assert_eq(Progress.total_stars(save), 3)
