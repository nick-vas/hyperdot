extends GutTest
## Hidden check for the alpha's add-content: track 3, Caldera Hairpins, is a clean loop with its checkpoints in order and
## hairpins, and a full-pace driver finishes it on the road in a fair time.

var tracks := Tracks.from_files()


func test_hidden_track_3_is_named_and_listed():
	assert_true(tracks.has_track(3))
	var row := tracks.row(3)
	assert_eq(row.get("name"), "TRACK_3")
	assert_eq(tr("TRACK_3"), "Caldera Hairpins")
	assert_eq(int(row.get("laps", 0)), 2)
	assert_between(float(row.get("width", 0)), 120.0, 200.0)


func test_hidden_its_checkpoints_go_round_in_order():
	var row := tracks.row(3)
	var checkpoints: Array = row.get("checkpoints", [])
	assert_gte(checkpoints.size(), 6)
	for k in range(1, checkpoints.size()):
		assert_gt(int(checkpoints[k]), int(checkpoints[k - 1]), "checkpoint %d after %d" % [k, k - 1])
	assert_lt(int(checkpoints[checkpoints.size() - 1]), row.points.size())


func test_hidden_the_road_never_runs_into_itself():
	var track := tracks.track(3)
	var n := track.point_count()
	var clearance := INF
	for i in n:
		for j in range(i + 30, n - 30 + i):
			clearance = minf(clearance, track.point(i).distance_to(track.point(j)))
	assert_gt(clearance, track.width + 60.0)


func test_hidden_it_has_hairpins():
	var track := tracks.track(3)
	var dips := 0
	var inside := track.speed_profile[track.point_count() - 1] < 250.0
	for i in track.point_count():
		var slow := track.speed_profile[i] < 250.0
		if slow and not inside:
			dips += 1
		inside = slow
	assert_gte(dips, 2, "bends the AI takes under 250 px/s")


func test_hidden_a_full_pace_driver_finishes_it_on_the_road():
	var race := Race.new(tracks.track(3), [AiDriver.new()], 60)
	var off := 0
	while race.finish_order.is_empty() and race.tick < 90 * 60:
		race.step()
		if not race.cars[0].on_road:
			off += 1
	assert_eq(race.finish_order, [0] as Array[int])
	assert_eq(off, 0, "ticks off the road")
	assert_between(race.tick / 60.0, 30.0, 70.0, "seconds for both laps")
