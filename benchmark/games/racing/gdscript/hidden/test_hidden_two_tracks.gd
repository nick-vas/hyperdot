extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: two tracks a driver can finish, and a save that keeps the
## best laps and the open tracks.

const PATH := "user://hidden_two_tracks_save.json"


func after_each():
	for path in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_hidden_two_tracks_a_driver_can_finish():
	var tracks := Tracks.from_files()
	for id in [1, 2]:
		assert_true(tracks.has_track(id), "track %d" % id)
		var race := Race.new(tracks.track(id), [AiDriver.new()], 60)
		while race.finish_order.is_empty() and race.tick < 120 * 60:
			race.step()
		assert_eq(race.finish_order, [0] as Array[int], "track %d finished" % id)
	assert_eq(tracks.row(2).get("name"), "TRACK_2")
	assert_ne(tr("TRACK_2"), "TRACK_2")


func test_hidden_the_save_keeps_best_laps_and_open_tracks():
	var store := SaveStore.new(PATH)
	var data := store.read()
	assert_eq(int(data.unlocked), 1)
	data.unlocked = 2
	data.best["2"] = 31250
	assert_true(store.write(data))
	var back := SaveStore.new(PATH).read()
	assert_eq(int(back.unlocked), 2)
	assert_eq(int(back.best["2"]), 31250)
