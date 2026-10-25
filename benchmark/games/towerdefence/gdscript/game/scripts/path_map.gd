class_name PathMap
extends RefCounted
## The field as a grid of cells: rocks and towers block, every other cell is open. Pests walk the shortest way from the
## gate (where they come in) to the seed store (where they leak), found by AStarGrid2D on four neighbours. The map only
## knows cells; Battle decides what may be built where.

const ROCK := "#"
const GATE := "S"
const STORE := "G"

var size := Vector2i.ZERO
var gate := Vector2i.ZERO
var store := Vector2i.ZERO
## Every path search the map ran, previews included: the performance tests read it.
var path_queries := 0
## The way from the gate to the store as the map stands, the gate first; empty when there is none.
var route: Array[Vector2i] = []

var _rocks := {}
var _towers := {}
var _astar := AStarGrid2D.new()


## A map from rows of text: "." open, "#" rock, "S" the gate, "G" the store.
static func from_rows(rows: Array) -> PathMap:
	var map := PathMap.new()
	map.size = Vector2i(str(rows[0]).length(), rows.size())
	map._astar.region = Rect2i(Vector2i.ZERO, map.size)
	map._astar.cell_size = Vector2.ONE
	map._astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	map._astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	map._astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	map._astar.update()
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var cell := Vector2i(x, y)
			match row[x]:
				ROCK:
					map._rocks[cell] = true
					map._astar.set_point_solid(cell, true)
				GATE:
					map.gate = cell
				STORE:
					map.store = cell
	map.route = map.path_from(map.gate)
	return map


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


func is_rock(cell: Vector2i) -> bool:
	return _rocks.has(cell)


## A pest may stand on it: inside the map, no rock and no tower.
func is_open(cell: Vector2i) -> bool:
	return in_bounds(cell) and not _rocks.has(cell) and not _towers.has(cell)


## A tower may stand on it, as far as the map goes: open, and neither the gate nor the store.
func is_buildable(cell: Vector2i) -> bool:
	return is_open(cell) and cell != gate and cell != store


## The shortest way from a cell to the store, that cell first; empty when the store cannot be reached from it.
func path_from(cell: Vector2i) -> Array[Vector2i]:
	path_queries += 1
	if not is_open(cell):
		return []
	return _astar.get_id_path(cell, store)


func set_tower(cell: Vector2i, standing: bool) -> void:
	if standing:
		_towers[cell] = true
	else:
		_towers.erase(cell)
	_astar.set_point_solid(cell, standing or _rocks.has(cell))
	route = path_from(gate)


## Whether a tower on this cell would leave the gate, or any of the cells pests are heading to, with no way to the store.
func blocks(cell: Vector2i, from_cells: Array[Vector2i]) -> bool:
	var was_solid := _astar.is_point_solid(cell)
	_astar.set_point_solid(cell, true)
	_towers[cell] = true
	var blocked := false
	var tried := {}
	for from: Vector2i in [gate] + from_cells:
		if tried.has(from):
			continue
		tried[from] = true
		if path_from(from).is_empty():
			blocked = true
			break
	_towers.erase(cell)
	_astar.set_point_solid(cell, was_solid)
	return blocked


## The route as it would be with a tower on this cell (empty when the tower would block it), for the bot's choices.
func preview_route(cell: Vector2i) -> Array[Vector2i]:
	var was_solid := _astar.is_point_solid(cell)
	_astar.set_point_solid(cell, true)
	_towers[cell] = true
	var preview := path_from(gate)
	_towers.erase(cell)
	_astar.set_point_solid(cell, was_solid)
	return preview
