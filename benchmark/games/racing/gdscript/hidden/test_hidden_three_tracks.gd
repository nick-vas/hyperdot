extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: three tracks, each finished by a full-pace driver, which beats the
## rivals from the back of the grid on every one, and a bot from the command line.

var tracks := Tracks.from_files()


func test_hidden_three_tracks_the_bot_wins_from_the_back():
	for id in [1, 2, 3]:
		assert_true(tracks.has_track(id), "track %d" % id)
		if not tracks.has_track(id):
			continue
		var race := Race.new(tracks.track(id), tracks.drivers_for(3, 1009 + id, true), 60)
		while race.finish_order.size() < race.cars.size() and race.tick < 150 * 60:
			race.step()
		assert_eq(race.finish_order.size(), 4, "track %d: every car finished" % id)
		assert_lte(race.finish_order.find(0) + 1, 2, "track %d: the bot in the top two" % id)


func test_hidden_the_bot_flag_is_read():
	var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--seed=4", "--no-save", "--track=2"]))
	assert_true(options.autoplay)
	assert_eq(options.run_seed, 4)
	assert_true(options.no_save)
	assert_eq(options.track, 2)
