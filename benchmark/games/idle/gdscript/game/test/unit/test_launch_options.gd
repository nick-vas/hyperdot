extends GutTest
## LaunchOptions: the flags bot runs and tests pass after "--".


func test_the_flags_are_read():
	var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--no-save", "--speed=60"]))
	assert_true(options.autoplay)
	assert_true(options.no_save)
	assert_eq(options.speed, 60.0)


func test_without_flags_the_game_plays_at_its_own_pace():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.autoplay)
	assert_false(options.no_save)
	assert_eq(options.speed, 1.0)


func test_the_speed_is_kept_within_bounds():
	assert_eq(LaunchOptions.parse(PackedStringArray(["--speed=0"])).speed, 1.0)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--speed=99999"])).speed, 600.0)
