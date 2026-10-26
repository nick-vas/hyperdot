extends GutTest
## Hidden check for the prototype's add-feature: Race.standings() and Race.position_of() rank the cars by the flag,
## then laps, then gates passed in the lap, then the distance left to the next gate, level cars by index.

var tracks := Tracks.from_files()


func _race(cars := 4) -> Race:
	return Race.new(tracks.track(1), tracks.drivers_for(cars - 1, 9), 60)


func test_hidden_the_grid_order_is_the_order_on_the_road():
	var race := _race()
	# Car 0 starts at the back; the others in grid order, front row first.
	assert_eq(race.standings(), [1, 2, 3, 0] as Array[int])
	for i in 4:
		assert_eq(race.position_of(i), race.standings().find(i) + 1)


func test_hidden_more_laps_lead():
	var race := _race()
	for t in race.trackers:
		t.armed = true
		t.next_gate = 2
	race.trackers[3].laps = 1
	race.trackers[0].laps = 2
	assert_eq(race.standings().slice(0, 2), [0, 3])


func test_hidden_more_gates_in_the_lap_lead():
	var race := _race()
	for t in race.trackers:
		t.armed = true
	race.trackers[2].next_gate = 3
	race.trackers[0].next_gate = 0
	race.trackers[1].next_gate = 1
	race.trackers[3].next_gate = 2
	assert_eq(race.standings(), [0, 2, 3, 1] as Array[int])


func test_hidden_the_closer_to_the_next_gate_leads():
	var race := _race(3)
	var track := race.track
	for i in 3:
		race.trackers[i].armed = true
		race.trackers[i].next_gate = 1
	var gate := track.gate_points[1]
	for i in 3:
		race.cars[i].position = track.point(gate - 3 - 4 * i)
		race.cars[i].index = track.nearest(race.cars[i].position)
	assert_eq(race.standings(), [0, 1, 2] as Array[int])
	race.cars[2].position = track.point(gate - 1)
	race.cars[2].index = track.nearest(race.cars[2].position)
	assert_eq(race.position_of(2), 1)


func test_hidden_level_cars_go_by_index():
	var race := _race(3)
	for i in 3:
		race.cars[i].position = race.cars[0].position
		race.cars[i].index = race.cars[0].index
	assert_eq(race.standings(), [0, 1, 2] as Array[int])


func test_hidden_the_flag_comes_first_in_its_order():
	var race := _race()
	race.trackers[1].laps = 9
	race.finish_order = [3, 0] as Array[int]
	assert_eq(race.standings().slice(0, 2), [3, 0])
	assert_eq(race.position_of(1), 3)


func test_hidden_a_real_race_ends_in_the_finish_order():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 9, true), 60)
	while race.finish_order.size() < 4 and race.tick < 120 * 60:
		race.step()
	assert_eq(race.standings(), race.finish_order)
