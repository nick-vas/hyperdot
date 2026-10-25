class_name Court
extends RefCounted
## A walled pit: its size, the pillars inside it and the four spawn points, from data/courts.json, data/walls.json and
## data/spawns.json. Everything is in whole pixels, and fighters collide with walls as squares, so the server and every
## client move a fighter to exactly the same place (no trigonometry, no rounding that could differ).

## Half the side of a fighter's square against walls.
const HALF := 16

var id := ""
var name_key := ""
var width := 1200
var height := 640
## Rect2i pillars.
var walls: Array[Rect2i] = []
## Vector2i spawn points, one per slot.
var spawns: Array[Vector2i] = []


## Every court in the data, in file order.
static func load_all(dir := "res://data") -> Array[Court]:
	var courts: Array[Court] = []
	var walls := _read(dir.path_join("walls.json"))
	var spawns := _read(dir.path_join("spawns.json"))
	for row: Dictionary in _read(dir.path_join("courts.json")):
		var court := Court.new()
		court.id = str(row.id)
		court.name_key = str(row.get("name", ""))
		court.width = int(row.width)
		court.height = int(row.height)
		for wall: Dictionary in walls:
			if str(wall.court) == court.id:
				court.walls.append(Rect2i(int(wall.x), int(wall.y), int(wall.w), int(wall.h)))
		for spawn: Dictionary in spawns:
			if str(spawn.court) == court.id:
				court.spawns.append(Vector2i(int(spawn.x), int(spawn.y)))
		courts.append(court)
	return courts


static func _read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Court: %s is not a JSON array" % path)
		return []
	return parsed


## Whether a fighter's square centred at (x, y) is inside the court and clear of every pillar.
func box_free(x: int, y: int) -> bool:
	if x < HALF or y < HALF or x > width - HALF or y > height - HALF:
		return false
	return _wall_at(x, y) == null


func _wall_at(x: int, y: int) -> Variant:
	var box := Rect2i(x - HALF, y - HALF, HALF * 2, HALF * 2)
	for wall in walls:
		if wall.intersects(box):
			return wall
	return null


## Moves a square by (dx, dy), one axis after the other, stopping flush against the court's edge or a pillar.
func slide(from: Vector2i, dx: int, dy: int) -> Vector2i:
	var x := clampi(from.x + dx, HALF, width - HALF)
	var wall: Variant = _wall_at(x, from.y)
	if wall != null:
		x = wall.position.x - HALF if dx > 0 else wall.end.x + HALF
	var y := clampi(from.y + dy, HALF, height - HALF)
	wall = _wall_at(x, y)
	if wall != null:
		y = wall.position.y - HALF if dy > 0 else wall.end.y + HALF
	return Vector2i(x, y)


## How far a ray from `from` along the unit vector `dir` travels before it meets a pillar or the court's edge.
func ray_length(from: Vector2, dir: Vector2, max_length: float) -> float:
	var best := max_length
	var bounds: Array[Rect2i] = [Rect2i(-10, -10, width + 20, 10), Rect2i(-10, height, width + 20, 10),
		Rect2i(-10, 0, 10, height), Rect2i(width, 0, 10, height)]
	for wall in walls + bounds:
		var t := _ray_rect(from, dir, wall)
		if t >= 0.0 and t < best:
			best = t
	return best


## Whether nothing stands between two points (bots use it to see).
func clear_line(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	if length < 0.001:
		return true
	return ray_length(a, (b - a) / length, length) >= length - 0.001


# The slab method: the distance along the ray to the rectangle, -1 when it misses.
static func _ray_rect(from: Vector2, dir: Vector2, rect: Rect2i) -> float:
	var t_min := 0.0
	var t_max := INF
	for axis in 2:
		var origin := from.x if axis == 0 else from.y
		var d := dir.x if axis == 0 else dir.y
		var low := float(rect.position.x if axis == 0 else rect.position.y)
		var high := float(rect.end.x if axis == 0 else rect.end.y)
		if absf(d) < 0.000001:
			if origin < low or origin > high:
				return -1.0
			continue
		var t1 := (low - origin) / d
		var t2 := (high - origin) / d
		t_min = maxf(t_min, minf(t1, t2))
		t_max = minf(t_max, maxf(t1, t2))
		if t_min > t_max:
			return -1.0
	return t_min
