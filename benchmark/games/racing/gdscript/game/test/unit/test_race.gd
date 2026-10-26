extends GutTest
## Race: the grid, the order of the finish, and a race that replays exactly from its grid and inputs.

var tracks := Tracks.from_files()


func _run(race: Race, seconds: float, input := Vector2.ZERO) -> void:
	for i in roundi(seconds * race.rate):
		race.step(input)


func test_the_player_starts_at_the_back_of_the_grid():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5), 60)
	assert_eq(race.cars.size(), 4)
	var line := race.track.lengths[race.track.gate_points[0]]
	var behind: Array[float] = []
	for car in race.cars:
		behind.append(fposmod(line - race.track.distance_along(car.position, car.index), race.track.length()))
	assert_eq(behind.max(), behind[0], "the player's car is furthest from the line")


func test_the_same_grid_and_inputs_drive_the_same_race():
	var a := Race.new(tracks.track(1), tracks.drivers_for(3, 11), 60)
	var b := Race.new(tracks.track(1), tracks.drivers_for(3, 11), 60)
	_run(a, 8.0, Vector2(1.0, 0.13))
	_run(b, 8.0, Vector2(1.0, 0.13))
	for i in a.cars.size():
		assert_eq(a.cars[i].position, b.cars[i].position, "car %d" % i)
		assert_eq(a.cars[i].heading, b.cars[i].heading, "car %d" % i)


func test_a_seed_shuffles_the_rivals_on_the_grid():
	var orders := {}
	for race_seed in 8:
		orders[str(tracks.grid_order(3, race_seed))] = true
	assert_gt(orders.size(), 1)


func test_the_cars_take_the_flag_in_order():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5, true), 60)
	var places: Array[int] = []
	race.car_finished.connect(func(car: int, place: int) -> void: places.append(place))
	while race.finish_order.size() < 4 and race.tick < 90 * 60:
		race.step()
	assert_eq(places, [1, 2, 3, 4] as Array[int])
	assert_eq(race.finish_order[0], 0, "the bot beats the rivals")


func test_every_lap_of_the_player_is_recorded_for_its_ghost():
	var race := Race.new(tracks.track(1), tracks.drivers_for(1, 5, true), 60)
	while race.trackers[0].laps < 2 and race.tick < 60 * 60:
		race.step()
	assert_not_null(race.best_ghost)
	assert_eq(race.best_ghost.ticks(), race.trackers[0].lap_times.min())
