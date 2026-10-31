class_name Sim
extends RefCounted
## The movement and shooting code the server and every client share. A client predicts its own glimmer with step(), the
## server applies the same inputs with step(), and because both run the same whole-number arithmetic the prediction is
## exactly what the server will say: a reconciled client never corrects anything (multiplayer).

## The simulation runs at the physics rate: 30 ticks a second.
const TICK_RATE := 30
## Pixels a tick moving along one axis, and along each axis moving diagonally (8 / sqrt(2), rounded).
const SPEED := 8
const DIAGONAL := 6
## A dash multiplies the speed for a few ticks, then needs a rest.
const DASH_FACTOR := 3
const DASH_TICKS := 5
const DASH_COOLDOWN := 45
## Ticks between two shots.
const FIRE_COOLDOWN := 12
## A shot is a ray this long; a fighter is a circle this big to it.
const RANGE := 1000.0
const RADIUS := 18.0


## An input that does nothing: a bot with nothing to do, or a player whose input has not arrived.
static func idle() -> Dictionary:
	return {"seq": 0, "mx": 0, "my": 0, "ax": 0, "ay": 0, "fire": false, "dash": false, "claim": -1}


## Clamps what a client sent to what an input can be: a server never trusts the wire.
static func sanitize(raw: Dictionary) -> Dictionary:
	var input := idle()
	input.seq = int(raw.get("seq", 0))
	input.mx = clampi(int(raw.get("mx", 0)), -1, 1)
	input.my = clampi(int(raw.get("my", 0)), -1, 1)
	input.ax = clampi(int(raw.get("ax", 0)), -10000, 10000)
	input.ay = clampi(int(raw.get("ay", 0)), -10000, 10000)
	input.fire = bool(raw.get("fire", false))
	input.dash = bool(raw.get("dash", false))
	input.claim = int(raw.get("claim", -1))
	return input


## One tick of a fighter under an input: timers, aim, dash and movement. Returns true when the input fires a shot (the
## caller traces it; the cooldown is already set).
static func step(f: Fighter, input: Dictionary, court: Court) -> bool:
	if not f.alive:
		return false
	f.cooldown = maxi(f.cooldown - 1, 0)
	f.dash_cooldown = maxi(f.dash_cooldown - 1, 0)
	if int(input.ax) != 0 or int(input.ay) != 0:
		f.ax = int(input.ax)
		f.ay = int(input.ay)
	if bool(input.get("dash", false)) and f.dash_cooldown == 0 and f.dash_ticks == 0:
		f.dash_ticks = DASH_TICKS
		f.dash_cooldown = DASH_COOLDOWN
	var mx := int(input.mx)
	var my := int(input.my)
	var speed := DIAGONAL if mx != 0 and my != 0 else SPEED
	if f.dash_ticks > 0:
		speed *= DASH_FACTOR
		f.dash_ticks -= 1
	var moved := court.slide(Vector2i(f.x, f.y), mx * speed, my * speed)
	f.x = moved.x
	f.y = moved.y
	if bool(input.fire) and f.cooldown == 0:
		f.cooldown = FIRE_COOLDOWN
		return true
	return false


## The shot a fighter fires along its aim: the first living fighter the ray meets before a wall, and where it ends.
## Returns { "target": slot or -1, "x", "y" }.
static func trace(court: Court, fighters: Array, shooter: int) -> Dictionary:
	var from: Fighter = fighters[shooter]
	var origin := from.position()
	var dir := from.aim()
	var reach := court.ray_length(origin, dir, RANGE)
	var target := -1
	for other: Fighter in fighters:
		if other.slot == shooter or not other.alive:
			continue
		var t := _ray_circle(origin, dir, other.position(), RADIUS)
		if t >= 0.0 and t < reach:
			reach = t
			target = other.slot
	var end := origin + dir * reach
	return {"target": target, "x": int(end.x), "y": int(end.y)}


# Distance along the ray to the circle, -1 when it misses or lies behind.
static func _ray_circle(origin: Vector2, dir: Vector2, center: Vector2, radius: float) -> float:
	var to_center := center - origin
	var along := to_center.dot(dir)
	if along < 0.0:
		return -1.0
	var miss := to_center.length_squared() - along * along
	if miss > radius * radius:
		return -1.0
	return maxf(along - sqrt(radius * radius - miss), 0.0)
