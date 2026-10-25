extends GutTest
## LaunchOptions: the flags runs and tests pass after "--".


func test_the_flags_are_read():
	var options := LaunchOptions.parse(PackedStringArray(["--no-save"]))
	assert_true(options.no_save)


func test_nothing_given_is_a_player_session():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.no_save)
