extends GutTest
## LaunchOptions: the flags bot runs, servers and soak pass after "--".

func test_the_flags_are_read():
	var options := LaunchOptions.parse(PackedStringArray(["--seed=7", "--no-save", "--lag=120", "--port=24660"]))
	assert_eq(options.run_seed, 7)
	assert_true(options.no_save)
	assert_eq(options.lag_ms, 120)
	assert_eq(options.port, 24660)
	assert_false(options.server)


func test_soak_roles():
	var server := LaunchOptions.parse(PackedStringArray(["--soak-role=server", "--soak-port=24661"]))
	assert_true(server.server)
	assert_eq(server.port, 24661)
	var client := LaunchOptions.parse(PackedStringArray(["--soak-role=client", "--soak-port=24661", "--soak-id=3"]))
	assert_false(client.server)
	assert_eq(client.soak_id, 3)


func test_no_flags():
	var options := LaunchOptions.parse(PackedStringArray())
	assert_false(options.autoplay)
	assert_eq(options.run_seed, 0)
	assert_eq(options.lag_ms, 0)
	assert_eq(options.port, LaunchOptions.DEFAULT_PORT)
	assert_eq(options.match_seed(1), 0)


func test_match_seeds_follow_the_run_seed():
	var options := LaunchOptions.parse(PackedStringArray(["--seed=2"]))
	assert_eq(options.match_seed(1), 2019)
	assert_eq(options.match_seed(2), 2020)
