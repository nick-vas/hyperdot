extends GutTest
## Hidden check for the beta's fix-bug: a ghost drives exactly the lap it recorded, tick by tick, after being saved and
## loaded, for a driver with analog throttle and steering (a gamepad, or the AI), on the opening lap and a flying one.

const PATH := "user://hidden_ghost_save.json"

var tracks := Tracks.from_files()


func after_each():
	for path in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Drives laps with an analog driver as the player's input; returns each lap's positions, tick by tick.
func _drive(race: Race, laps: int) -> Array[PackedVector2Array]:
	var brain := AiDriver.new(0.937, 7.5)
	var out: Array[PackedVector2Array] = [PackedVector2Array()]
	while race.trackers[0].laps < laps and race.tick < 120 * race.rate:
		var done := race.trackers[0].laps
		race.step(brain.decide(race.cars[0], race.track))
		out[out.size() - 1].append(race.cars[0].position)
		if race.trackers[0].laps > done:
			out.append(PackedVector2Array())
	return out


func _round_trip(ghost: Ghost) -> Ghost:
	var store := SaveStore.new(PATH)
	var data := SaveStore.defaults()
	SaveStore.record_lap(data, 2, 1, ghost)
	store.write(data)
	return Ghost.from_dict(store.read().ghosts.get("2"))


func _worst_gap(driven: PackedVector2Array, replayed: PackedVector2Array) -> float:
	var worst := 0.0
	for t in mini(driven.size(), replayed.size()):
		worst = maxf(worst, driven[t].distance_to(replayed[t]))
	return worst


func test_hidden_the_opening_lap_replays_exactly():
	var race := Race.new(tracks.track(2), [null], 60)
	var first := race.ghost
	var laps := _drive(race, 1)
	var replayed := _round_trip(first).replay(race.track)
	assert_eq(replayed.size(), laps[0].size(), "as many ticks as the lap")
	assert_lt(_worst_gap(laps[0], replayed), 0.01, "pixels apart at worst")


func test_hidden_the_best_flying_lap_replays_exactly():
	var race := Race.new(tracks.track(2), [null], 60)
	var laps := _drive(race, 2)
	assert_eq(race.best_ghost.ticks(), race.trackers[0].lap_times.min())
	var best := 0 if race.trackers[0].lap_times[0] <= race.trackers[0].lap_times[1] else 1
	var replayed := _round_trip(race.best_ghost).replay(race.track)
	assert_eq(replayed.size(), laps[best].size())
	assert_lt(_worst_gap(laps[best], replayed), 0.01, "pixels apart at worst")


func test_hidden_the_replay_crosses_the_line_on_the_lap_time():
	var race := Race.new(tracks.track(2), [null], 60)
	_drive(race, 2)
	var ghost := _round_trip(race.best_ghost)
	var tracker := LapTracker.new()
	tracker.armed = true
	var car := ghost.start_car()
	car.index = race.track.nearest(car.position)
	var crossed_at := -1
	for t in ghost.ticks():
		var from := car.position
		ghost.drive(car, t, race.track)
		if tracker.update(race.track, from, car.position, t + 1) == LapTracker.Crossing.LAP and crossed_at < 0:
			crossed_at = t + 1
	assert_eq(crossed_at, race.trackers[0].best_lap)
