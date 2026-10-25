extends GutTest
## LaunchOptions: the flags runs and tests pass after "--".


func test_every_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--seed=7", "--no-save", "--track=3", "--rivals=7"]))
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.track, 3)
	assert_eq(options.rivals, 7)


func test_no_flags_is_a_normal_game():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.no_save)
	assert_eq(options.track, 1)
	assert_eq(options.rivals, 3)


func test_out_of_range_values_are_held_in_range():
	var options := LaunchOptions.parse(PackedStringArray(["--track=0", "--rivals=99"]))
	assert_eq(options.track, 1)
	assert_eq(options.rivals, 31)
