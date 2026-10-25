extends Node2D
## The floor's walls and stones, drawn once per floor (and again when the stairs open): they never move, so they are not
## drawn with the creatures every frame.

const TILE := 22
const WALL_COLOR := Color(0.13, 0.11, 0.15)
const EDGE_COLOR := Color(0.24, 0.2, 0.27)
const FLOOR_COLOR := Color(0.33, 0.29, 0.25)
const STONE_COLOR := Color(0.37, 0.33, 0.28)
const STAIRS_SHUT := Color(0.25, 0.22, 0.3)
const STAIRS_OPEN := Color(0.98, 0.78, 0.36)

var dungeon: Dungeon
var world: World


func show_dungeon(floor_dungeon: Dungeon, floor_world: World) -> void:
	dungeon = floor_dungeon
	world = floor_world
	queue_redraw()


func _draw() -> void:
	if dungeon == null:
		return
	draw_rect(Rect2(Vector2(-6, -6), Vector2(dungeon.width * TILE + 12, dungeon.height * TILE + 12)), WALL_COLOR)
	for y in dungeon.height:
		for x in dungeon.width:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(x * TILE, y * TILE), Vector2(TILE, TILE))
			if dungeon.is_floor(cell):
				draw_rect(rect, STONE_COLOR if (x + y) % 2 == 0 else FLOOR_COLOR)
			elif _touches_floor(cell):
				draw_rect(rect.grow(-2), EDGE_COLOR)
	var stairs := Rect2(Vector2(dungeon.stairs) * TILE, Vector2(TILE, TILE))
	var open := world != null and world.stairs_open
	draw_rect(stairs.grow(-2), STAIRS_OPEN if open else STAIRS_SHUT)
	for step in 3:
		draw_line(stairs.position + Vector2(4, 6 + step * 5), stairs.position + Vector2(TILE - 4, 6 + step * 5), WALL_COLOR, 2.0)


func _touches_floor(cell: Vector2i) -> bool:
	for dir in Dungeon.DIRS:
		if dungeon.is_floor(cell + dir):
			return true
	return false
