extends Node2D
## Draws the battle: the grid, rocks, the gate, the pests' route, towers, pests, shots and the rings left where
## something happened. It only reads the battle; the game node decides.

const ORIGIN := Vector2(66, 120)
const CELL := 54.0
const POP_SECONDS := 0.4
const GRASS := [Color(0.2, 0.32, 0.16), Color(0.22, 0.35, 0.18)]
const ROCK_COLOR := Color(0.36, 0.33, 0.3)
const GATE_COLOR := Color(0.12, 0.2, 0.09)
const ROUTE_COLOR := Color(0.95, 0.85, 0.55, 0.35)
const TOWER_COLORS := {"thorn": Color(0.55, 0.85, 0.35), "puff": Color(0.95, 0.85, 0.35), "acorn": Color(0.7, 0.45, 0.25)}
const ENEMY_COLORS := {"aphid": Color(0.6, 0.95, 0.5), "beetle": Color(0.25, 0.3, 0.55), "moth": Color(0.85, 0.75, 0.95), "slug_queen": Color(0.75, 0.35, 0.6)}

var battle: Battle
var selected := Vector2i(-1, -1)
var _pops: Array[Dictionary] = []


func show_battle(next_battle: Battle) -> void:
	battle = next_battle
	_pops.clear()
	queue_redraw()


## A battle position (in cells) on screen.
func to_screen(pos: Vector2) -> Vector2:
	return ORIGIN + pos * CELL


func cell_centre(cell: Vector2i) -> Vector2:
	return to_screen(Enemy.centre(cell))


func cell_at(local: Vector2) -> Vector2i:
	var at := (local - ORIGIN) / CELL
	return Vector2i(floori(at.x), floori(at.y))


## A ring that grows and fades where something happened.
func pop(at: Vector2, color: Color) -> void:
	_pops.append({"at": at, "color": color, "left": POP_SECONDS})
	queue_redraw()


func _process(delta: float) -> void:
	if _pops.is_empty():
		return
	for p in _pops:
		p.left -= delta
	_pops = _pops.filter(func(p: Dictionary) -> bool: return p.left > 0.0)
	queue_redraw()


func _draw() -> void:
	if battle == null:
		return
	var map := battle.map
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			var rect := Rect2(ORIGIN + Vector2(cell) * CELL, Vector2(CELL, CELL))
			draw_rect(rect, GRASS[(x + y) % 2])
			if map.is_rock(cell):
				draw_rect(rect.grow(-4), ROCK_COLOR)
	draw_rect(Rect2(ORIGIN + Vector2(map.gate) * CELL, Vector2(CELL, CELL)).grow(-6), GATE_COLOR)
	for step in map.route:
		draw_circle(cell_centre(step), 5.0, ROUTE_COLOR)
	if battle.towers.has(selected):
		var reach := float(battle.catalog.stats(battle.towers[selected].id, battle.towers[selected].level)["range"])
		draw_arc(cell_centre(selected), reach * CELL, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	for cell: Vector2i in battle.towers:
		_draw_tower(cell, battle.towers[cell])
	for enemy in battle.enemies:
		_draw_enemy(enemy)
	for shot in battle.shots:
		draw_circle(to_screen(shot.pos), 5.0 if float(shot.splash) > 0.0 else 3.5, TOWER_COLORS.get(shot.tower, Color.WHITE).lightened(0.3))
	for p in _pops:
		var t := 1.0 - float(p.left) / POP_SECONDS
		var color: Color = p.color
		color.a = 1.0 - t
		draw_arc(p.at, 10.0 + 30.0 * t, 0.0, TAU, 32, color, 3.0)


func _draw_tower(cell: Vector2i, tower: Dictionary) -> void:
	var at := cell_centre(cell)
	var k := CELL / 64.0
	var color: Color = TOWER_COLORS.get(tower.id, Color.WHITE)
	match str(tower.id):
		"thorn":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -24) * k, at + Vector2(20, 18) * k, at + Vector2(-20, 18) * k]), color)
		"puff":
			draw_circle(at, 22.0 * k, color)
			draw_circle(at, 10.0 * k, color.darkened(0.3))
		_:
			draw_rect(Rect2(at - Vector2(20, 20) * k, Vector2(40, 40) * k), color)
			draw_circle(at, 9.0 * k, color.darkened(0.4))
	if selected == cell:
		draw_rect(Rect2(at - Vector2(28, 28) * k, Vector2(56, 56) * k), Color.WHITE, false, 2.0)
	for i in int(tower.level):
		draw_circle(at + Vector2(-12 + 12 * i, 26) * k, 3.5, Color(1, 1, 1, 0.9))


func _draw_enemy(enemy: Enemy) -> void:
	var at := to_screen(enemy.pos)
	var radius := float(battle.catalog.enemies[enemy.id].get("size", 0.25)) * CELL
	draw_circle(at, radius, ENEMY_COLORS.get(enemy.id, Color.WHITE))
	if enemy.slow_ticks > 0:
		draw_arc(at, radius + 3.0, 0.0, TAU, 24, Color(0.95, 0.85, 0.35, 0.8), 2.0)
	var share := clampf(float(enemy.hp) / enemy.max_hp, 0.0, 1.0)
	draw_rect(Rect2(at + Vector2(-radius, -radius - 8), Vector2(radius * 2.0, 4)), Color(0.2, 0.05, 0.05))
	draw_rect(Rect2(at + Vector2(-radius, -radius - 8), Vector2(radius * 2.0 * share, 4)), Color(0.9, 0.25, 0.2))
