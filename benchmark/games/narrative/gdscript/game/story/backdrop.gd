extends Control
## The river behind the text, drawn in code: night sky, water, the ferry with the stranger and the lantern, the fog of
## the crossing and the far bank with its drowned tower. The lantern glows when the stranger's trust grows.

const SKY := Color(0.05, 0.07, 0.11)
const WATER := Color(0.07, 0.13, 0.17)
const WATER_LINE := Color(0.12, 0.2, 0.25)
const BANK := Color(0.03, 0.05, 0.06)
const BOAT := Color(0.24, 0.16, 0.1)
const FIGURE := Color(0.5, 0.53, 0.56)
const LANTERN := Color(1.0, 0.8, 0.42)

const LANTERN_TEXTURE := preload("res://art/lantern.png")

## The chapter of the line shown: 1 the landing, 2 the crossing in fog, 3 the far bank.
var chapter := 1:
	set(value):
		if value != chapter:
			chapter = value
			queue_redraw()
## How brightly the lantern glows, 0 to 1; it fades on its own.
var glow := 0.0:
	set(value):
		if not is_equal_approx(value, glow):
			glow = value
			queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var horizon := h * 0.42
	draw_rect(Rect2(0, 0, w, horizon), SKY)
	draw_rect(Rect2(0, horizon, w, h - horizon), WATER)
	for i in 6:
		var y := horizon + 24.0 + i * (h - horizon) / 6.0
		draw_line(Vector2(w * 0.08 * i, y), Vector2(w * (0.4 + 0.08 * i), y), WATER_LINE, 2.0)
	if chapter == 1:
		# The Hensmouth landing on the left: a jetty and the town's lights.
		draw_rect(Rect2(0, horizon - 40, w * 0.3, 40), BANK)
		for i in 5:
			draw_circle(Vector2(30 + i * 70, horizon - 54), 4.0, LANTERN.darkened(0.3))
	if chapter == 3:
		# The Greywick bank on the right and the broken tower in the shallows.
		draw_rect(Rect2(w * 0.65, horizon - 50, w * 0.35, 50), BANK)
		draw_rect(Rect2(w * 0.56, horizon - 150, 46, 170), BANK)
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.56, horizon - 150), Vector2(w * 0.56 + 46, horizon - 150), Vector2(w * 0.56 + 30, horizon - 186)]), BANK)
	_draw_ferry(Vector2(w * 0.74, horizon + (h - horizon) * 0.35))
	if chapter == 2:
		draw_rect(Rect2(0, 0, w, h), Color(0.6, 0.65, 0.7, 0.28))


func _draw_ferry(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-170, 0), at + Vector2(170, 0), at + Vector2(130, 34), at + Vector2(-130, 34)]), BOAT)
	# The stranger, seated at the bow, and the lantern on its pole at the stern.
	draw_rect(Rect2(at + Vector2(60, -58), Vector2(34, 58)), FIGURE)
	draw_circle(at + Vector2(77, -72), 16.0, FIGURE)
	draw_line(at + Vector2(-120, 0), at + Vector2(-120, -90), BOAT.lightened(0.2), 4.0)
	var lamp := at + Vector2(-120, -100)
	draw_circle(lamp, 26.0 + 30.0 * glow, Color(LANTERN, 0.12 + 0.3 * glow))
	draw_texture(LANTERN_TEXTURE, lamp - LANTERN_TEXTURE.get_size() / 2.0, Color(1, 1, 1).lerp(Color(1.3, 1.2, 0.9), glow))
