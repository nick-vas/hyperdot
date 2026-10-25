extends GutTest
## LaunchOptions: the flags runs and tests pass after "--".


func test_every_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--seed=7", "--no-save", "--map=3", "--speed=2"]))
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.map, 3)
	assert_eq(options.speed, 2)


func test_no_flags_give_the_defaults():
	var options := LaunchOptions.parse(PackedStringArray([]))
	assert_eq(options.run_seed, 0)
	assert_false(options.no_save)
	assert_eq(options.map, 1)
	assert_eq(options.speed, 1)
