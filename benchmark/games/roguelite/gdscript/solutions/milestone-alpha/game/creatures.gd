extends Node2D
## The wick and the enemies, drawn each frame where they are sliding between cells, and the rings left where an enemy
## was snuffed. One node draws them all, so a swarm of hundreds costs one draw pass, not hundreds of nodes.

const TILE := 22
const FLASH_TICKS := 6
## Seconds a snuffed enemy's ring takes to fade.
const POP_SECONDS := 0.4
const WICK_TEXTURE := preload("res://art/wick.png")
const COLORS := {"shade": Color(0.55, 0.36, 0.78), "bat": Color(0.86, 0.47, 0.24), "brute": Color(0.72, 0.24, 0.2)}

var world: World
var _pops: Array[Dictionary] = []


func show_world(floor_world: World) -> void:
	world = floor_world
	_pops.clear()
	queue_redraw()


## A ring where an enemy was snuffed.
func pop(cell: Vector2i) -> void:
	_pops.append({"at": (Vector2(cell) + Vector2(0.5, 0.5)) * TILE, "age": 0.0})


func advance(delta: float) -> void:
	for ring in _pops:
		ring.age += delta
	_pops = _pops.filter(func(ring: Dictionary) -> bool: return ring.age < POP_SECONDS)
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var glow := _place(world.wick)
	draw_circle(glow, TILE * 2.6, Color(1.0, 0.8, 0.4, 0.07))
	for enemy in world.enemies:
		var at := _place(enemy)
		var color: Color = COLORS.get(enemy.kind, Color.GRAY)
		if world.tick - enemy.hit_at < FLASH_TICKS:
			color = Color.WHITE
		match enemy.kind:
			"bat":
				draw_colored_polygon(PackedVector2Array([at + Vector2(-9, -4), at + Vector2(9, -4), at + Vector2(0, 7)]), color)
			"brute":
				draw_rect(Rect2(at - Vector2(9, 9), Vector2(18, 18)), color)
			_:
				draw_circle(at, 8.0, color)
		if enemy.alert > 0:
			draw_circle(at + Vector2(-3, -2), 1.6, Color(1.0, 0.9, 0.6))
			draw_circle(at + Vector2(3, -2), 1.6, Color(1.0, 0.9, 0.6))
	var wick_color := Color(1, 1, 1, 0.45) if world.wick.mercy > 0 and world.tick % 8 < 4 else Color.WHITE
	draw_texture(WICK_TEXTURE, glow - Vector2(WICK_TEXTURE.get_size()) / 2.0, wick_color)
	for ring in _pops:
		var t: float = ring.age / POP_SECONDS
		draw_arc(ring.at, 6.0 + t * 16.0, 0.0, TAU, 20, Color(1.0, 0.75, 0.35, 1.0 - t), 2.0)


## Where an actor is drawn: sliding from the cell it left to its cell over one step's ticks.
func _place(actor: Actor) -> Vector2:
	var t := clampf(float(world.tick - actor.moved_at) / maxf(actor.move_ticks, 1.0), 0.0, 1.0)
	return (Vector2(actor.from_cell).lerp(Vector2(actor.cell), t) + Vector2(0.5, 0.5)) * TILE
