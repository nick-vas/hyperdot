class_name Fighter
extends RefCounted
## One glimmer in the pit: where it is, where it aims, its health and its timers. The server holds the true ones; a
## client holds copies from snapshots, and predicts its own.

var slot := 0
var x := 0
var y := 0
## The last direction aimed, as a vector of whole numbers (any length).
var ax := 1
var ay := 0
var hp := 3
var alive := false
## Ticks until it can fire again.
var cooldown := 0
## Ticks of dash left, and ticks until the next dash.
var dash_ticks := 0
var dash_cooldown := 0


func position() -> Vector2:
	return Vector2(x, y)


func aim() -> Vector2:
	var v := Vector2(ax, ay)
	return v / v.length() if v.length() > 0.0 else Vector2.RIGHT


func copy() -> Fighter:
	return Fighter.from_array(to_array())


## The wire form: a flat array of whole numbers, small in a snapshot.
func to_array() -> Array:
	return [slot, x, y, ax, ay, hp, 1 if alive else 0, cooldown, dash_ticks, dash_cooldown]


static func from_array(data: Array) -> Fighter:
	var f := Fighter.new()
	f.slot = int(data[0])
	f.x = int(data[1])
	f.y = int(data[2])
	f.ax = int(data[3])
	f.ay = int(data[4])
	f.hp = int(data[5])
	f.alive = int(data[6]) == 1
	f.cooldown = int(data[7])
	f.dash_ticks = int(data[8])
	f.dash_cooldown = int(data[9])
	return f
