extends GutTest
## Hidden check for the prototype's fix-bug: a lap counts only when every checkpoint was crossed in order. Skipping
## one, over the grass or by moves fed straight to the tracker, never makes a lap; going back for it does.

var track := Tracks.from_files().track(1)


func _cross(tracker: LapTracker, gate: int, tick: int) -> LapTracker.Crossing:
	var i := track.gate_points[gate]
	var along := track.tangent(i) * 20.0
	return tracker.update(track, track.point(i) - along, track.point(i) + along, tick)


## Moves the car along a polyline in steps of at most 12 pixels, from tick on; returns the laps made.
func _drive(tracker: LapTracker, points: Array, tick := 1) -> int:
	for k in points.size() - 1:
		var a: Vector2 = points[k]
		var b: Vector2 = points[k + 1]
		var steps := maxi(ceili(a.distance_to(b) / 12.0), 1)
		for s in steps:
			tracker.update(track, a.lerp(b, float(s) / steps), a.lerp(b, float(s + 1) / steps), tick)
			tick += 1
	return tracker.laps


func test_hidden_every_gate_in_order_is_a_lap():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 1)
	for g in range(1, track.gate_count()):
		_cross(tracker, g, 100 * g)
	assert_eq(_cross(tracker, 0, 900), LapTracker.Crossing.LAP)
	assert_eq(tracker.laps, 1)


func test_hidden_a_skipped_gate_makes_no_lap():
	for skipped in range(1, track.gate_count()):
		var tracker := LapTracker.new()
		_cross(tracker, 0, 1)
		for g in range(1, track.gate_count()):
			if g != skipped:
				_cross(tracker, g, 100 * g)
		_cross(tracker, 0, 900)
		assert_eq(tracker.laps, 0, "gate %d skipped" % skipped)


func test_hidden_going_back_for_a_skipped_gate_makes_the_lap():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 1)
	_cross(tracker, 1, 100)
	_cross(tracker, 3, 200)
	_cross(tracker, 2, 300)
	_cross(tracker, 3, 400)
	_cross(tracker, 0, 500)
	assert_eq(tracker.laps, 1)
	assert_eq(tracker.last_lap(), 500)


func test_hidden_gates_out_of_order_make_no_lap():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 1)
	_cross(tracker, 1, 100)
	_cross(tracker, 3, 200)
	_cross(tracker, 2, 300)
	_cross(tracker, 0, 400)
	assert_eq(tracker.laps, 0)


func test_hidden_a_lap_driven_backwards_does_not_count():
	var tracker := LapTracker.new()
	_cross(tracker, 0, 1)
	var tick := 2
	for g in [3, 2, 1, 0, 3, 2, 1, 0]:
		var i := track.gate_points[g]
		var along := track.tangent(i) * 20.0
		tracker.update(track, track.point(i) + along, track.point(i) - along, tick)
		tick += 50
	assert_eq(tracker.laps, 0)


func test_hidden_a_shortcut_across_the_infield_makes_no_lap():
	var tracker := LapTracker.new()
	var line := track.point(track.gate_points[0])
	# Off the grid over the line, then straight up across the grass to the far straight, and round to the line.
	var path: Array = [line + Vector2(-200, 0), line + Vector2(300, 0), Vector2(0, -490)]
	var far := track.nearest(Vector2(0, -490))
	var i := far
	while posmod(i, track.point_count()) != track.gate_points[0]:
		i += 1
		path.append(track.point(i))
	path.append(line + Vector2(150, 0))
	assert_eq(_drive(tracker, path), 0, "the lap skipped the far gates")
	assert_true(tracker.armed)


func test_hidden_the_whole_lap_on_the_road_counts():
	var tracker := LapTracker.new()
	var start := track.gate_points[0]
	var path: Array = [track.point(start - 3)]
	for k in track.point_count() + 4:
		path.append(track.point(start - 2 + k))
	assert_eq(_drive(tracker, path), 1)
