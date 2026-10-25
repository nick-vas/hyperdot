class_name CarView
extends Node2D
## A car drawn from above: a body, a windscreen and four wheels, pointing along +x. A ghost is drawn as an outline.

const LENGTH := 34.0
const WIDTH := 18.0

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
	for wheel: Vector2 in [Vector2(-10, -10), Vector2(10, -10), Vector2(-10, 10), Vector2(10, 10)]:
		draw_rect(Rect2(wheel - Vector2(5, 3), Vector2(10, 6)), Color("#1b1b1b"))
	draw_rect(body, color)
	draw_rect(Rect2(Vector2(2, -7), Vector2(7, 14)), Color("#2b3a4a"))
	draw_rect(body, color.darkened(0.4), false, 2.0)
