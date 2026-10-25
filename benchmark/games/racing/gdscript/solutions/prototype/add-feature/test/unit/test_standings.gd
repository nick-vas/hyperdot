extends GutTest
## Race.standings: who leads, from the flag back to the cars on their first lap.

var tracks := Tracks.from_files()


func test_on_the_grid_the_front_row_leads():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5), 60)
	assert_eq(race.standings(), [1, 2, 3, 0] as Array[int])
	assert_eq(race.position_of(0), 4)


func test_a_car_a_lap_ahead_leads():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5), 60)
	race.trackers[0].armed = true
	race.trackers[0].laps = 1
	assert_eq(race.position_of(0), 1)


func test_a_car_past_more_gates_leads():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5), 60)
	race.trackers[3].armed = true
	race.trackers[3].next_gate = 2
	race.trackers[2].armed = true
	race.trackers[2].next_gate = 1
	assert_eq(race.standings().slice(0, 2), [3, 2])


func test_those_who_took_the_flag_lead_in_their_order():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5), 60)
	race.finish_order = [2, 0] as Array[int]
	race.trackers[1].laps = 5
	assert_eq(race.standings().slice(0, 2), [2, 0])


func test_the_bot_climbs_from_the_back_in_a_race():
	var race := Race.new(tracks.track(1), tracks.drivers_for(3, 5, true), 60)
	for i in 20 * 60:
		race.step()
	assert_eq(race.position_of(0), 1)
