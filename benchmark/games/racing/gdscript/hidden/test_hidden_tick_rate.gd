extends GutTest
## Hidden check for the beta's fix-playthrough: the handling is the same at any physics tick rate. A straight run tops
## out at ACCEL / DRAG, and a driver's laps take the same time, at 30, 60, 120 and 144 ticks a second.

var tracks := Tracks.from_files()


func _top_speed(rate: int) -> float:
	var car := Car.new()
	for i in 10 * rate:
		car.step(1.0, 0.0, 1.0 / rate)
	return car.speed


## Seconds a full-pace driver alone takes for the track's laps at a tick rate.
func _race_seconds(track_id: int, rate: int) -> float:
	var race := Race.new(tracks.track(track_id), [AiDriver.new()], rate)
	while race.finish_order.is_empty() and race.tick < 150 * rate:
		race.step()
	return race.tick / float(rate)


func test_hidden_the_top_speed_is_the_same_at_every_tick_rate():
	for rate in [30, 60, 120, 144]:
		assert_almost_eq(_top_speed(rate), Car.ACCEL / Car.DRAG, Car.ACCEL / Car.DRAG * 0.01, "%d ticks a second" % rate)


func test_hidden_a_race_takes_the_same_time_at_30_and_144_ticks():
	for track_id in [1, 3]:
		var at_60 := _race_seconds(track_id, 60)
		for rate in [30, 120, 144]:
			assert_almost_eq(_race_seconds(track_id, rate), at_60, at_60 * 0.015, "track %d at %d ticks against 60" % [track_id, rate])


func test_hidden_the_car_is_as_quick_as_designed():
	# The three laps of Ashfall Oval take a full-pace driver about 28 s at the designed handling.
	assert_between(_race_seconds(1, 120), 26.0, 30.0)
