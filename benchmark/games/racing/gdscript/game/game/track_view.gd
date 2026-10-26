extends Node2D
## Draws a track: the ash around it, the road along the path, the kerbs, the checkpoint gates and the chequered line.

const GROUND := Color("#3a2f2a")
const ROAD := Color("#5b5f66")
const KERB := Color("#c8553d")
const KERB_LIGHT := Color("#e8e0d0")
const GATE := Color(1, 1, 1, 0.18)
const CINDER := Color("#2a2220")
const EMBER := Color("#7a3b22")

var track: Track


func show_track(shown: Track) -> void:
	track = shown
	queue_redraw()


func _draw() -> void:
	if track == null:
		return
	var box := Rect2(track.path[0], Vector2.ZERO)
	for p in track.path:
		box = box.expand(p)
	draw_rect(box.grow(1600.0), GROUND)
	_draw_cinders(box.grow(1600.0))
	var loop := track.path.duplicate()
	loop.append(track.path[0])
	for i in track.point_count():
		var colour := KERB if (i / 2) % 2 == 0 else KERB_LIGHT
		draw_line(track.point(i), track.point(i + 1), colour, track.width + 14.0)
		draw_circle(track.point(i), track.width / 2.0 + 7.0, colour)
	draw_polyline(loop, ROAD, track.width)
	for p in track.path:
		draw_circle(p, track.width / 2.0, ROAD)
	for gate in range(1, track.gate_count()):
		var ends := track.gate_ends(gate)
		draw_line(ends[0], ends[1], GATE, 4.0)
	_draw_line_chequers()


func _draw_line_chequers() -> void:
	var i := track.gate_points[0]
	var along := track.tangent(i)
	var across := along.orthogonal()
	var squares := 10
	var size := track.width / squares
	for row in 2:
		for k in squares:
			var corner := track.point(i) + across * (k * size - track.width / 2.0) + along * (row * size)
			var colour := Color.WHITE if (k + row) % 2 == 0 else Color.BLACK
			draw_colored_polygon(PackedVector2Array([corner, corner + across * size, corner + across * size + along * size, corner + along * size]), colour)


## Scattered cinders and embers on the ground: the same every time (a fixed seed), and drawn once.
func _draw_cinders(area: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + track.id
	for k in 900:
		var at := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		draw_circle(at, rng.randf_range(3.0, 11.0), EMBER if k % 9 == 0 else CINDER)
