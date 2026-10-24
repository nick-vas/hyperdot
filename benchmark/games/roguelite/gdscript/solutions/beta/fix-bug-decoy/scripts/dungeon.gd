class_name Dungeon
extends RefCounted
## One floor of the crypt, generated from a seed: walls and floor on a grid, rectangular rooms joined by corridors, where
## the wick starts, the stairs down and where each enemy waits. Pure data, built before any node: the same seed and
## floor give the same dungeon on every machine, so a seed from a bug report rebuilds the floor and a test can sweep
## hundreds of seeds in moments.

const WALL := 0
const FLOOR := 1
## The four steps a creature can take, in the order every search and choice tries them.
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## The letter of each kind in to_text() and from_text().
const KIND_LETTERS := {"shade": "s", "bat": "b", "brute": "B"}
## Room placements tried before the generator settles for fewer rooms than it rolled.
const PLACE_TRIES := 400

var width := 0
var height := 0
## WALL or FLOOR per cell, row by row (index y * width + x).
var tiles := PackedByteArray()
## Room 0 is where the wick starts.
var rooms: Array[Rect2i] = []
var start := Vector2i.ZERO
var stairs := Vector2i.ZERO
## Each enemy to place: { "kind", "cell" }, in the order they were rolled.
var spawns: Array[Dictionary] = []


## spec: a floor of data/floors.json (width, height, rooms [min, max], room_size [min, max], enemies, per_room [min, max]).
static func generate(seed_value: int, spec: Dictionary) -> Dungeon:
	var dungeon := Dungeon.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# One seed for every draw, the global ones too.
	seed(seed_value)
	dungeon.width = int(spec.width)
	dungeon.height = int(spec.height)
	dungeon.tiles.resize(dungeon.width * dungeon.height)
	dungeon.tiles.fill(WALL)
	dungeon._place_rooms(rng, spec)
	dungeon._join_rooms(rng)
	dungeon.start = dungeon.center(0)
	dungeon.stairs = dungeon._farthest_room_center()
	dungeon._place_spawns(rng, spec)
	return dungeon


func _place_rooms(rng: RandomNumberGenerator, spec: Dictionary) -> void:
	var wanted := rng.randi_range(int(spec.rooms[0]), int(spec.rooms[1]))
	var low := int(spec.room_size[0])
	var high := int(spec.room_size[1])
	for i in PLACE_TRIES:
		if rooms.size() >= wanted:
			break
		var size := Vector2i(randi_range(low, high), rng.randi_range(low, high))
		var rect := Rect2i(Vector2i(rng.randi_range(1, width - size.x - 1), rng.randi_range(1, height - size.y - 1)), size)
		# At least one wall between two rooms, so a room's shape stays readable.
		var free := true
		for room in rooms:
			if room.grow(1).intersects(rect):
				free = false
				break
		if free:
			rooms.append(rect)
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					tiles[y * width + x] = FLOOR


## Each room after the first is dug to the nearest room already joined: a spanning tree grown from room 0, so every room
## can be reached from the start whatever the seed.
func _join_rooms(rng: RandomNumberGenerator) -> void:
	for i in range(1, rooms.size()):
		var nearest := 0
		var best := 1 << 30
		for j in i:
			var gap := _manhattan(center(i), center(j))
			if gap < best:
				best = gap
				nearest = j
		_dig_corridor(center(i), center(nearest), rng.randi() % 2 == 0)


## An L-shaped corridor: across then down, or down then across.
func _dig_corridor(from: Vector2i, to: Vector2i, across_first: bool) -> void:
	var corner := Vector2i(to.x, from.y) if across_first else Vector2i(from.x, to.y)
	_dig_line(from, corner)
	_dig_line(corner, to)


func _dig_line(from: Vector2i, to: Vector2i) -> void:
	var step := (to - from).sign()
	var cell := from
	tiles[index(cell)] = FLOOR
	while cell != to:
		cell += step
		tiles[index(cell)] = FLOOR


## The stairs go in the room whose centre is the longest walk from the start, so a floor is crossed, not skipped.
func _farthest_room_center() -> Vector2i:
	var field := distance_field(start)
	var best := center(0)
	var best_distance := -1
	for i in range(1, rooms.size()):
		var distance := field[index(center(i))]
		if distance > best_distance:
			best_distance = distance
			best = center(i)
	return best


## Every room but the start holds per_room enemies, each of a kind drawn from the floor's list (repeats weigh more).
func _place_spawns(rng: RandomNumberGenerator, spec: Dictionary) -> void:
	var kinds: Array = spec.enemies
	var taken := {start: true, stairs: true}
	for i in range(1, rooms.size()):
		var room := rooms[i]
		var count := rng.randi_range(int(spec.per_room[0]), int(spec.per_room[1]))
		for n in count:
			var cell := Vector2i(rng.randi_range(room.position.x, room.end.x - 1), rng.randi_range(room.position.y, room.end.y - 1))
			var kind := str(kinds[rng.randi_range(0, kinds.size() - 1)])
			if taken.has(cell):
				continue
			taken[cell] = true
			spawns.append({"kind": kind, "cell": cell})


func center(room: int) -> Vector2i:
	return rooms[room].position + rooms[room].size / 2


func index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func is_floor(cell: Vector2i) -> bool:
	return in_bounds(cell) and tiles[index(cell)] == FLOOR


## Steps from `from` to every cell over floor (a breadth-first search, four ways); -1 where it cannot be reached.
func distance_field(from: Vector2i) -> PackedInt32Array:
	var field := PackedInt32Array()
	field.resize(width * height)
	field.fill(-1)
	if not is_floor(from):
		return field
	var queue: Array[Vector2i] = [from]
	field[index(from)] = 0
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var next_distance := field[index(cell)] + 1
		for dir in DIRS:
			var next := cell + dir
			if is_floor(next) and field[index(next)] < 0:
				field[index(next)] = next_distance
				queue.append(next)
	return field


## Whether nothing but floor lies on the straight line between two cells (Bresenham, the ends not counted).
func line_clear(from: Vector2i, to: Vector2i) -> bool:
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var error := dx + dy
	var cell := from
	while cell != to:
		var twice := 2 * error
		if twice >= dy:
			error += dy
			cell.x += sx
		if twice <= dx:
			error += dx
			cell.y += sy
		if cell != to and not is_floor(cell):
			return false
	return true


## Floor cells the start cannot reach: 0 on a valid floor.
func unreachable_cells() -> int:
	var field := distance_field(start)
	var count := 0
	for i in tiles.size():
		if tiles[i] == FLOOR and field[i] < 0:
			count += 1
	return count


func floor_cells() -> int:
	return tiles.count(FLOOR)


## The floor as text, one row per line: # wall, . floor, S start, > stairs, a letter per spawn (KIND_LETTERS). Two
## dungeons are the same when their text is.
func to_text() -> String:
	var rows := PackedStringArray()
	for y in height:
		var row := ""
		for x in width:
			row += "." if tiles[y * width + x] == FLOOR else "#"
		rows.append(row)
	for spawn in spawns:
		var cell: Vector2i = spawn.cell
		var letter := str(KIND_LETTERS.get(spawn.kind, str(spawn.kind).substr(0, 1)))
		rows[cell.y] = rows[cell.y].substr(0, cell.x) + letter + rows[cell.y].substr(cell.x + 1)
	rows[start.y] = rows[start.y].substr(0, start.x) + "S" + rows[start.y].substr(start.x + 1)
	rows[stairs.y] = rows[stairs.y].substr(0, stairs.x) + ">" + rows[stairs.y].substr(stairs.x + 1)
	return "\n".join(rows)


## A floor drawn by hand in to_text()'s letters, for tests: every cell that is not # is floor, and the whole floor is
## one room.
static func from_text(rows: PackedStringArray) -> Dungeon:
	var dungeon := Dungeon.new()
	dungeon.height = rows.size()
	dungeon.width = rows[0].length()
	dungeon.tiles.resize(dungeon.width * dungeon.height)
	dungeon.tiles.fill(WALL)
	dungeon.rooms.append(Rect2i(0, 0, dungeon.width, dungeon.height))
	var kinds := {}
	for kind: String in KIND_LETTERS:
		kinds[KIND_LETTERS[kind]] = kind
	for y in dungeon.height:
		for x in dungeon.width:
			var letter := rows[y][x]
			var cell := Vector2i(x, y)
			if letter == "#":
				continue
			dungeon.tiles[dungeon.index(cell)] = FLOOR
			if letter == "S":
				dungeon.start = cell
			elif letter == ">":
				dungeon.stairs = cell
			elif kinds.has(letter):
				dungeon.spawns.append({"kind": kinds[letter], "cell": cell})
	return dungeon


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
