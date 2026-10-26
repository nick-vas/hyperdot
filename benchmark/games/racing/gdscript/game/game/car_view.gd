class_name CarView
extends Node2D
## A car drawn from above: a body, a windscreen and four wheels, pointing along +x. A ghost is drawn as an outline.

const LENGTH := 40.0
const WIDTH := 22.0

var color := Color("#f2c14e"):
	set(value):
		color = value
		queue_redraw()
var ghost := false:
	set(value):
		ghost = value
		queue_redraw()


func _draw() -> void:
	var half := Vector2(LENGTH, WIDTH) / 2.0
	var body := Rect2(-half, half * 2.0)
	if ghost:
		draw_rect(body, color, false, 3.0)
		return
	for wheel: Vector2 in [Vector2(-12, -12), Vector2(12, -12), Vector2(-12, 12), Vector2(12, 12)]:
		draw_rect(Rect2(wheel - Vector2(6, 3), Vector2(12, 6)), Color("#1b1b1b"))
	draw_rect(body, color)
	draw_rect(Rect2(Vector2(3, -8), Vector2(8, 16)), Color("#2b3a4a"))
	draw_rect(Rect2(Vector2(-18, -3), Vector2(14, 6)), color.lightened(0.35))
	draw_rect(body, color.darkened(0.4), false, 2.0)
