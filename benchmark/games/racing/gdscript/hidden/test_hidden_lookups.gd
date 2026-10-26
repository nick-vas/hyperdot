extends GutTest
## Hidden check for the beta's fix-performance: finding the track segment under each car costs a few segment checks a
## tick, however many rivals race, and finds the same segment a search of the whole loop finds, also for a car that
## left the road or was put somewhere new.

var tracks := Tracks.from_files()


## The nearest segment by looking at all of them, without touching the track's counter.
func _nearest_everywhere(track: Track, at: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for i in track.point_count():
		var d := at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at, track.point(i), track.point(i + 1)))
		if d < best_distance:
			best_distance = d
			best = i
	return best


func _same_segment(track: Track, at: Vector2, found: int, expected: int) -> bool:
	if found == expected:
		return true
	var a := at.distance_to(Geometry2D.get_closest_point_to_segment(at, track.point(found), track.point(found + 1)))
	var b := at.distance_to(Geometry2D.get_closest_point_to_segment(at, track.point(expected), track.point(expected + 1)))
	return absf(a - b) < 0.001


func test_hidden_a_full_grid_costs_a_few_checks_a_car_a_tick():
	var race := Race.new(tracks.track(3), tracks.drivers_for(11, 5, true), 60)
	race.track.lookups = 0
	for i in 600:
		race.step()
	var per_car_tick := race.track.lookups / float(600 * race.cars.size())
	assert_lt(per_car_tick, 24.0, "segment checks per car per tick (the loop has %d)" % race.track.point_count())


func test_hidden_every_car_is_on_the_segment_a_full_search_finds():
	var race := Race.new(tracks.track(2), tracks.drivers_for(7, 3, true), 60)
	var wrong := 0
	for i in 900:
		race.step()
		for car in race.cars:
			if not _same_segment(race.track, car.position, car.index, _nearest_everywhere(race.track, car.position)):
				wrong += 1
	assert_eq(wrong, 0)


func test_hidden_a_car_off_the_road_or_moved_is_found_again():
	var race := Race.new(tracks.track(1), [null], 60)
	for i in 60:
		race.step(Vector2(1.0, 0.0))
	# Straight across the grass infield to the far straight, a few pixels a tick, then dropped at the far end.
	var car := race.cars[0]
	var spots: Array[Vector2] = []
	for k in 60:
		spots.append(car.position.lerp(Vector2(0, -480), (k + 1) / 60.0))
	spots.append(Vector2(-1250, 0))
	spots.append(Vector2(900, 420))
	for spot in spots:
		car.position = spot
		car.speed = 0.0
		race.step(Vector2.ZERO)
		assert_true(_same_segment(race.track, car.position, car.index, _nearest_everywhere(race.track, car.position)), "at %s" % car.position)


func test_hidden_a_ghost_still_replays_its_lap():
	var race := Race.new(tracks.track(1), [AiDriver.new()], 60)
	var path := PackedVector2Array()
	while race.trackers[0].laps < 1:
		race.step()
		path.append(race.cars[0].position)
	var replayed := race.best_ghost.replay(race.track)
	assert_eq(replayed.size(), path.size())
	assert_almost_eq(replayed[replayed.size() - 1].distance_to(path[path.size() - 1]), 0.0, 0.01)
