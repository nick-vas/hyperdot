class_name Enemy
extends RefCounted
## One pest on the field. Positions are in cells: (0.5, 0.5) is the middle of the top-left cell. A pest walks from cell
## centre to cell centre along its path, the cell it is heading to first.

## How long a slowing hit lasts, in ticks.
const SLOW_TICKS := 60

var uid := 0
var id := ""
var hp := 1
var max_hp := 1
## Cells per tick.
var speed := 0.0
var reward := 0
var leak := 1
var pos := Vector2.ZERO
var path: Array[Vector2i] = []
var alive := true
## The share of its speed a slowing hit takes, while slow_ticks lasts.
var slow := 0.0
var slow_ticks := 0


static func centre(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


## The cell it is heading to; its own cell once it has nowhere to go.
func target() -> Vector2i:
	return path[0] if not path.is_empty() else cell()


## How far it still has to walk, in cells: what towers compare to find the pest closest to the store.
func remaining() -> float:
	if path.is_empty():
		return 0.0
	return pos.distance_to(centre(path[0])) + float(path.size() - 1)


## How far it walks this tick.
func pace() -> float:
	return speed * (1.0 - slow) if slow_ticks > 0 else speed
