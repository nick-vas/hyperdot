extends GutTest
## Track: the path through the control points, the road, the gates and the grid.

var tracks := Tracks.from_files()
var track: Track


func before_each():
	track = tracks.track(1)


func test_the_path_passes_through_every_control_point():
	var row := tracks.row(1)
	for i in row.points.size():
		var p: Array = row.points[i]
		assert_almost_eq(track.point(i * Track.SUB).distance_to(Vector2(p[0], p[1])), 0.0, 0.01)


func test_the_loop_length_adds_up_its_segments():
	var total := 0.0
	for i in track.point_count():
		total += track.point(i).distance_to(track.point(i + 1))
	assert_almost_eq(track.length(), total, 0.5)


func test_nearest_with_a_hint_finds_what_a_full_search_finds():
	for i in range(0, track.point_count(), 7):
		var near := track.point(i) + track.tangent(i).orthogonal() * 30.0 + track.tangent(i) * 5.0
		assert_eq(track.nearest(near, posmod(i - 2, track.point_count())), track.nearest(near), "point %d" % i)


func test_the_road_is_as_wide_as_the_data_says():
	var i := 33
	var across := track.tangent(i).orthogonal()
	assert_true(track.is_on_road(track.point(i) + across * (track.width / 2.0 - 2.0), i))
	assert_false(track.is_on_road(track.point(i) + across * (track.width / 2.0 + 2.0), i))


func test_a_gate_counts_only_in_the_direction_of_travel():
	var i := track.gate_points[1]
	var along := track.tangent(i) * 20.0
	assert_true(track.crosses_gate(1, track.point(i) - along, track.point(i) + along))
	assert_false(track.crosses_gate(1, track.point(i) + along, track.point(i) - along))


func test_a_move_beside_the_gate_does_not_cross_it():
	var i := track.gate_points[1]
	var along := track.tangent(i) * 20.0
	var beside := track.tangent(i).orthogonal() * (track.width / 2.0 + Track.GATE_MARGIN + 30.0)
	assert_false(track.crosses_gate(1, track.point(i) - along + beside, track.point(i) + along + beside))


func test_the_grid_is_on_the_road_behind_the_line():
	var line := track.lengths[track.gate_points[0]]
	for slot in 4:
		var place: Dictionary = track.grid_slot(slot)
		var at: Vector2 = place.position
		var i := track.nearest(at)
		assert_true(track.is_on_road(at, i), "slot %d on the road" % slot)
		var behind := fposmod(line - track.distance_along(at, i), track.length())
		assert_between(behind, 40.0, 400.0, "slot %d behind the line" % slot)


func test_every_track_is_a_clean_loop():
	for row: Dictionary in tracks.rows:
		var t := Track.from_row(row)
		var n := t.point_count()
		var clearance := INF
		for i in n:
			for j in range(i + 30, n - 30 + i):
				clearance = minf(clearance, t.point(i).distance_to(t.point(j)))
		assert_gt(clearance, t.width + 60.0, "track %d does not run into itself" % t.id)
