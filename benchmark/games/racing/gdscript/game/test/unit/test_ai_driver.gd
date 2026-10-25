extends GutTest
## AiDriver: alone on each track it finishes its laps without leaving the road, and a slower pace is slower.

var tracks := Tracks.from_files()


func _alone(track_id: int, pace: float) -> Race:
	var race := Race.new(tracks.track(track_id), [AiDriver.new(pace)], Engine.physics_ticks_per_second)
	return race


func test_the_driver_finishes_every_track_on_the_road():
	for row: Dictionary in tracks.rows:
		var race := _alone(int(row.id), 1.0)
		var off := 0
		while race.finish_order.is_empty() and race.tick < 120 * race.rate:
			race.step()
			if not race.cars[0].on_road:
				off += 1
		assert_eq(race.finish_order, [0] as Array[int], "track %d finished" % row.id)
		assert_eq(off, 0, "track %d: ticks off the road" % row.id)


func test_a_slower_pace_takes_longer():
	var fast := _alone(1, 1.0)
	var slow := _alone(1, 0.85)
	while fast.finish_order.is_empty() and fast.tick < 60 * fast.rate:
		fast.step()
	while slow.finish_order.is_empty() and slow.tick < 60 * slow.rate:
		slow.step()
	assert_gt(slow.trackers[0].best_lap, fast.trackers[0].best_lap)


func test_the_driver_brakes_before_a_hairpin():
	var track := tracks.track(3)
	var slowest := 0
	for i in track.point_count():
		if track.speed_profile[i] < track.speed_profile[slowest]:
			slowest = i
	var car := Car.new()
	car.index = posmod(slowest - 8, track.point_count())
	car.position = track.point(car.index)
	car.heading = track.tangent(car.index).angle()
	car.speed = Car.ACCEL / Car.DRAG
	assert_lt(AiDriver.new().decide(car, track).x, 0.0)
