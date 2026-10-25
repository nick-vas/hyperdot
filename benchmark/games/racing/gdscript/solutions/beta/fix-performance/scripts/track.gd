class_name Track
extends RefCounted
## A closed track: its centre line, the road's width and the checkpoint gates, built once from a row of
## data/tracks.json. The control points are smoothed into a dense path (a Catmull-Rom spline through them, SUB points a
## segment), which the cars, the AI and the camera all read. Everything is plain arithmetic on the path, so a race runs
## the same without a scene.

## Dense points per control segment.
const SUB := 10
## Gates reach this far past each edge of the road, so a car running wide over the line still crosses it.
const GATE_MARGIN := 40.0
## How many segments either side of a car's last segment its next nearest one is looked for.
const SEARCH_BACK := 3
const SEARCH_AHEAD := 8
## The AI's speed limit through a bend: lateral grip and full lock both bound how tight the car can turn.
const CORNER_SAFETY := 0.92
## The braking the speed profile plans with, a little under the car's own.
const PLANNED_BRAKE := 700.0

var id := 0
var name_key := ""
var laps := 2
var width := 150.0
var path := PackedVector2Array()
## Distance along the path to each point, from point 0; the last entry is the whole loop.
var lengths := PackedFloat64Array()
## The dense index of each gate; gate 0 is the start and finish line.
var gate_points := PackedInt32Array()
## The fastest the AI plans to be at each point.
var speed_profile := PackedFloat64Array()
## Segments examined by nearest(), for the performance test.
var lookups := 0


static func from_row(row: Dictionary) -> Track:
	var track := Track.new()
	track.id = int(row.get("id", 0))
	track.name_key = str(row.get("name", ""))
	track.laps = int(row.get("laps", 2))
	track.width = float(row.get("width", 150.0))
	var controls: Array[Vector2] = []
	for p: Variant in row.get("points", []):
		controls.append(Vector2(float(p[0]), float(p[1])))
	track._build(controls)
	for c: Variant in row.get("checkpoints", [0]):
		track.gate_points.append(int(c) * SUB)
	track._plan_speeds()
	return track


func _build(controls: Array[Vector2]) -> void:
	var n := controls.size()
	for i in n:
		var p0 := controls[(i - 1 + n) % n]
		var p1 := controls[i]
		var p2 := controls[(i + 1) % n]
		var p3 := controls[(i + 2) % n]
		for s in SUB:
			var t := float(s) / SUB
			var t2 := t * t
			var t3 := t2 * t
			path.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	var total := 0.0
	for i in path.size():
		lengths.append(total)
		total += path[i].distance_to(path[(i + 1) % path.size()])
	lengths.append(total)


## The AI's speed at each point: no faster than the bend there allows, and slow enough to brake for every bend ahead.
func _plan_speeds() -> void:
	var n := path.size()
	var safe := PackedFloat64Array()
	safe.resize(n)
	for i in n:
		var radius := _radius_at(i)
		safe[i] = minf(sqrt(Car.GRIP * radius), radius * Car.TURN_RATE) * CORNER_SAFETY
	speed_profile = safe.duplicate()
	# Twice round the loop backwards, so the bends just past the line limit the speed before it too.
	for pass_number in 2:
		for k in n:
			var i := n - 1 - k
			var next := (i + 1) % n
			var ds := segment_length(i)
			speed_profile[i] = minf(speed_profile[i], sqrt(speed_profile[next] * speed_profile[next] + 2.0 * PLANNED_BRAKE * ds))


## The radius of the circle through the points either side of i (a straight is very large).
func _radius_at(i: int) -> float:
	var n := path.size()
	var a := path[(i - 2 + n) % n]
	var b := path[i]
	var c := path[(i + 2) % n]
	var cross := absf((b - a).cross(c - b))
	if cross < 0.0001:
		return 100000.0
	return a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * cross)


func point_count() -> int:
	return path.size()


func length() -> float:
	return lengths[lengths.size() - 1]


func segment_length(i: int) -> float:
	return lengths[i + 1] - lengths[i]


func point(i: int) -> Vector2:
	return path[posmod(i, path.size())]


## The direction of travel at a point.
func tangent(i: int) -> Vector2:
	return (point(i + 1) - point(i - 1)).normalized()


## The nearest segment to a position: the index of its first point. With a hint (the segment the car was on last tick)
## only the segments around it are looked at, and the whole loop only when that finds nothing on or near the road
## (a car placed somewhere new, or cutting across the grass).
func nearest(position: Vector2, hint := -1) -> int:
	if hint >= 0:
		var best := -1
		var best_distance := INF
		for k in range(-SEARCH_BACK, SEARCH_AHEAD + 1):
			var i := posmod(hint + k, path.size())
			var d := _segment_distance_squared(position, i)
			if d < best_distance:
				best_distance = d
				best = i
		if best_distance <= width * width:
			return best
	return _nearest_anywhere(position)


func _nearest_anywhere(position: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for i in path.size():
		var d := _segment_distance_squared(position, i)
		if d < best_distance:
			best_distance = d
			best = i
	return best


func _segment_distance_squared(position: Vector2, i: int) -> float:
	lookups += 1
	var a := path[i]
	var b := path[(i + 1) % path.size()]
	return position.distance_squared_to(Geometry2D.get_closest_point_to_segment(position, a, b))


## How far a position is from the centre line, measured on segment i.
func offset_from_centre(position: Vector2, i: int) -> float:
	var a := point(i)
	var b := point(i + 1)
	return position.distance_to(Geometry2D.get_closest_point_to_segment(position, a, b))


func is_on_road(position: Vector2, i: int) -> bool:
	return offset_from_centre(position, i) <= width / 2.0


## Distance along the loop of a position projected on segment i.
func distance_along(position: Vector2, i: int) -> float:
	var a := point(i)
	var b := point(i + 1)
	var span := b - a
	var t := clampf((position - a).dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
	return lengths[posmod(i, path.size())] + t * span.length()


func gate_count() -> int:
	return gate_points.size()


## The two ends of a gate, across the road.
func gate_ends(gate: int) -> PackedVector2Array:
	var i := gate_points[gate]
	var across := tangent(i).orthogonal() * (width / 2.0 + GATE_MARGIN)
	return PackedVector2Array([point(i) - across, point(i) + across])


## Whether a move from one position to the next crosses a gate in the direction of travel.
func crosses_gate(gate: int, from: Vector2, to: Vector2) -> bool:
	if (to - from).dot(tangent(gate_points[gate])) <= 0.0:
		return false
	var ends := gate_ends(gate)
	return Geometry2D.segment_intersects_segment(from, to, ends[0], ends[1]) != null


## A place on the starting grid behind the line: slot 0 is the front, each row two cars side by side.
func grid_slot(slot: int) -> Dictionary:
	if path.size() < 2 or gate_points.is_empty():
		return {"position": Vector2.ZERO, "heading": 0.0}
	var back := 60.0 + 70.0 * (slot / 2)
	var j := gate_points[0]
	var walked := 0.0
	while walked < back:
		j = posmod(j - 1, path.size())
		walked += segment_length(j)
	var direction := tangent(j)
	var side := (-1.0 if slot % 2 == 0 else 1.0) * width / 4.0
	return {"position": point(j) + direction.orthogonal() * side, "heading": direction.angle()}
