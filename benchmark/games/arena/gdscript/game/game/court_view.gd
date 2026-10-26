extends Node2D
## Draws the pit from the client: the court and its pillars, every glimmer where this screen shows it (its own
## predicted, the others interpolated), shots as fading beams, a ring where a glimmer was knocked out, and a white
## flash on a glimmer that was hit. It decides nothing.

const BEAM_SECONDS := 0.18
const POP_SECONDS := 0.45
const FLASH_SECONDS := 0.15

var client: ArenaClient
var origin := Vector2.ZERO
var colors: Array = []

var _beams: Array[Dictionary] = []
var _pops: Array[Dictionary] = []
var _flashes := {}


func beam(from: Vector2, to: Vector2, color: Color) -> void:
	_beams.append({"from": from, "to": to, "color": color, "left": BEAM_SECONDS})


func pop(at: Vector2) -> void:
	_pops.append({"at": at, "left": POP_SECONDS})


func flash_fighter(slot: int) -> void:
	_flashes[slot] = FLASH_SECONDS


func _physics_process(delta: float) -> void:
	for list: Array[Dictionary] in [_beams, _pops]:
		for item in list:
			item.left -= delta
		list.assign(list.filter(func(item: Dictionary) -> bool: return item.left > 0.0))
	for slot: int in _flashes.keys():
		_flashes[slot] -= delta
		if _flashes[slot] <= 0.0:
			_flashes.erase(slot)


func _draw() -> void:
	if client == null:
		return
	var court := client.view.court
	draw_rect(Rect2(origin, Vector2(court.width, court.height)), Color(0.1, 0.09, 0.13))
	draw_rect(Rect2(origin, Vector2(court.width, court.height)), Color(0.45, 0.4, 0.55), false, 4.0)
	for wall in court.walls:
		draw_rect(Rect2(origin + Vector2(wall.position), Vector2(wall.size)), Color(0.32, 0.28, 0.4))
	for f in client.shown_fighters():
		if not f.alive:
			continue
		var at := origin + f.position()
		var color: Color = colors[f.slot] if f.slot < colors.size() else Color.WHITE
		draw_circle(at, Sim.RADIUS, Color.WHITE if _flashes.has(f.slot) else color)
		draw_line(at, at + f.aim() * 30.0, color.lightened(0.4), 4.0)
		if f.slot == client.slot:
			draw_arc(at, Sim.RADIUS + 6.0, 0.0, TAU, 32, Color.WHITE, 2.0)
	for b in _beams:
		var fade: float = b.left / BEAM_SECONDS
		draw_line(origin + b.from, origin + b.to, Color(b.color, fade), 3.0)
	for p in _pops:
		var grown: float = 1.0 - p.left / POP_SECONDS
		draw_arc(origin + p.at, 20.0 + grown * 50.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.6, 1.0 - grown), 4.0)
