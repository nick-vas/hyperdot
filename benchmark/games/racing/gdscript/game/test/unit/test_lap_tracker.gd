extends GutTest
## LapTracker: the start line arms it, the gates in order make a lap, and lap times are the ticks between the lines.

var track := Tracks.from_files().track(1)


## Moves a car across a gate, 20 pixels either side of it, at the given tick.
func _cross(tracker: LapTracker, gate: int, tick: int) -> LapTracker.Crossing:
	var i := track.gate_points[gate]
	var along := track.tangent(i) * 20.0
	return tracker.update(track, track.point(i) - along, track.point(i) + along, tick)


## A whole lap from the line: every checkpoint in order, then the line, the last at end_tick.
func _lap(tracker: LapTracker, start_tick: int, end_tick: int) -> void:
	var gates := track.gate_count()
	for g in range(1, gates):
		_cross(tracker, g, start_tick + (end_tick - start_tick) * g / gates)
	_cross(tracker, 0, end_tick)


func test_the_first_crossing_of_the_line_only_arms_the_tracker():
	var tracker := LapTracker.new()
	assert_eq(_cross(tracker, 0, 20), LapTracker.Crossing.GATE)
	assert_true(tracker.armed)
	assert_eq(tracker.laps, 0)
	assert_eq(tracker.next_gate, 1)


func test_every_checkpoint_in_order_then_the_line_is_a_lap():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 20)
	_lap(tracker, 20, 600)
	assert_eq(tracker.laps, 1)
	assert_eq(tracker.next_gate, 1)


func test_the_first_lap_is_timed_from_the_start():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 20)
	_lap(tracker, 20, 600)
	assert_eq(tracker.last_lap(), 600)


func test_a_lap_time_is_the_ticks_between_two_crossings_of_the_line():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 20)
	_lap(tracker, 20, 600)
	_lap(tracker, 600, 900)
	assert_eq(tracker.lap_times, [600, 300] as Array[int])


func test_the_best_lap_is_the_fastest():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 20)
	_lap(tracker, 20, 600)
	_lap(tracker, 600, 900)
	_lap(tracker, 900, 1250)
	assert_eq(tracker.best_lap, 300)
	assert_eq(tracker.laps, 3)


func test_crossing_the_line_again_without_the_checkpoints_is_no_lap():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 20)
	assert_eq(_cross(tracker, 0, 80), LapTracker.Crossing.NONE)
	assert_eq(tracker.laps, 0)


func test_gates_passed_counts_the_lap_in_progress():
	var tracker := LapTracker.new()
	assert_eq(tracker.gates_passed(track), 0)
	_cross(tracker, 0, 20)
	_cross(tracker, 1, 120)
	assert_eq(tracker.gates_passed(track), 2)
