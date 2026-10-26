extends GutTest
## LaunchOptions: the flags bot runs and tests pass after "--".


func test_every_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--seed=7", "--no-save", "--map=3", "--speed=2"]))
	assert_true(options.autoplay)
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.map, 3)
	assert_eq(options.speed, 2)


func test_no_flags_give_the_defaults():
	var options := LaunchOptions.parse(PackedStringArray([]))
	assert_false(options.autoplay)
	assert_eq(options.run_seed, 0)
	assert_false(options.no_save)
	assert_eq(options.map, 1)
	assert_eq(options.speed, 1)


func test_a_bot_run_plays_fast_unless_told_otherwise():
	assert_eq(LaunchOptions.parse(PackedStringArray(["--autoplay"])).speed, 3)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--autoplay", "--speed=1"])).speed, 1)
