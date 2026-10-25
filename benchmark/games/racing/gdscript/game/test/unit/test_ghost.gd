extends GutTest
## Ghost: inputs kept in hundredths, saved and loaded, and a lap played back the way it was driven.

var tracks := Tracks.from_files()


func test_an_input_is_kept_in_hundredths():
	assert_eq(Ghost.quantize(0.123), 0.12)
	assert_eq(Ghost.quantize(-0.987), -0.99)
	assert_eq(Ghost.quantize(3.0), 1.0)


func test_a_recording_reads_back_its_inputs():
	var ghost := Ghost.new({"position": Vector2(1, 2), "heading": 0.5, "speed": 10.0})
	ghost.record(1.0, -0.5)
	ghost.record(0.0, 0.25)
	assert_eq(ghost.ticks(), 2)
	assert_eq(ghost.input_at(0), Vector2(1.0, -0.5))
	assert_eq(ghost.input_at(1), Vector2(0.0, 0.25))
	assert_eq(ghost.input_at(2), Vector2.ZERO, "nothing after the end")


func test_saved_and_loaded_it_is_the_same_ghost():
	var ghost := Ghost.new({"position": Vector2(-512.25, 300.5), "heading": 1.25, "speed": 333.0}, 60)
	for i in 30:
		ghost.record(1.0 if i % 3 else -1.0, 1.0 if i % 2 else 0.0)
	var copy := Ghost.from_dict(JSON.parse_string(JSON.stringify(ghost.to_dict())))
	assert_eq(copy.ticks(), 30)
	assert_eq(copy.start.position, ghost.start.position)
	assert_eq(copy.throttles, ghost.throttles)
	assert_eq(copy.steers, ghost.steers)


func test_damaged_data_is_no_ghost():
	assert_null(Ghost.from_dict("lap"))
	assert_null(Ghost.from_dict({"start": {}, "throttle": [1, 2], "steer": [1]}))


## A lap on the keys (full or nothing), the way a keyboard player drives it, replays exactly.
func test_a_lap_on_the_keys_replays_exactly():
	var race := Race.new(tracks.track(1), [null], 60)
	var brain := AiDriver.new()
	var path := PackedVector2Array()
	while race.trackers[0].laps < 1 and race.tick < 40 * 60:
		var wish := brain.decide(race.cars[0], race.track)
		race.step(Vector2(signf(wish.x), signf(snappedf(wish.y, 0.5))))
		path.append(race.cars[0].position)
	assert_eq(race.trackers[0].laps, 1)
	var replayed := race.best_ghost.replay(race.track)
	assert_eq(replayed.size(), path.size())
	assert_almost_eq(replayed[replayed.size() - 1].distance_to(path[path.size() - 1]), 0.0, 0.01)
