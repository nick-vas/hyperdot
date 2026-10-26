extends Control
## The dusk behind the hive: motes of glow drifting up, more of them the more glow there is, drawn as circles.

const MOST_MOTES := 48

## The glow to show; Game sets it every tick.
var glow := 0.0
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var area := size
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.07, 0.06, 0.12))
	draw_circle(Vector2(area.x * 0.8, area.y * 0.12), 60.0, Color(0.95, 0.85, 0.55, 0.25))
	var motes := clampi(4 + int(String.num(floorf(maxf(glow, 1.0))).length()) * 3, 4, MOST_MOTES)
	for i in motes:
		# Fixed lanes and phases, so the sky moves the same way every time.
		var lane := fmod(i * 0.618034, 1.0)
		var rise := fmod(_time * (0.02 + 0.01 * fmod(i * 0.37, 1.0)) + i * 0.13, 1.0)
		var at := Vector2(lane * area.x + sin(_time + i) * 12.0, area.y * (1.0 - rise))
		draw_circle(at, 3.0 + fmod(i * 0.71, 1.0) * 4.0, Color(1.0, 0.82, 0.4, 0.35 + 0.4 * (1.0 - rise)))
