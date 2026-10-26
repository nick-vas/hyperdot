class_name Bot
extends RefCounted
## A bot that fills an empty slot, so a match always has four glimmers and needs no second machine. It keeps a fighting
## distance from the nearest rival it can see, circles it, aims with a seeded error and fires when it has a line. The
## server's bots read the true match; a client's bot (--autoplay) reads the client's copy, as a player would see it.

## Pixels it tries to keep from its target.
const NEAR := 220.0
const FAR := 420.0
## Ticks between changes of its circling direction, and the most its aim is off, in pixels at the target.
const THINK_TICKS := 24
const AIM_ERROR := 26
## Chance of firing on a tick it can.
const TRIGGER := 0.35

var slot := 0
var rng := RandomNumberGenerator.new()
var _circle := 1
var _ticks := 0


func _init(bot_slot := 0, bot_seed := 1) -> void:
	slot = bot_slot
	rng.seed = bot_seed


## The input for this tick. `me` is the fighter to steer (a client passes its predicted one); the match's by default.
func decide(arena: ArenaMatch, me: Fighter = null) -> Dictionary:
	var input := Sim.idle()
	if me == null:
		me = arena.fighters[slot]
	if arena.state != ArenaMatch.State.ROUND or not me.alive:
		return input
	_ticks += 1
	if _ticks % THINK_TICKS == 0 and rng.randf() < 0.4:
		_circle = -_circle
	var target := _pick_target(arena, me)
	if target == null:
		return input
	var here := me.position()
	var there := target.position()
	var seen := arena.court.clear_line(here, there)
	var to := there - here
	var distance := to.length()
	var move := Vector2.ZERO
	if not seen or distance > FAR:
		move = to
	elif distance < NEAR:
		move = -to
	else:
		move = Vector2(-to.y, to.x) * _circle
	var step := _free_direction(arena.court, me, move)
	input.mx = step.x
	input.my = step.y
	input.ax = int(to.x) + rng.randi_range(-AIM_ERROR, AIM_ERROR)
	input.ay = int(to.y) + rng.randi_range(-AIM_ERROR, AIM_ERROR)
	input.fire = seen and me.cooldown <= 1 and rng.randf() < TRIGGER
	input.dash = not seen and distance > FAR and rng.randf() < 0.02
	return input


# The nearest living rival, one in sight first.
func _pick_target(arena: ArenaMatch, me: Fighter) -> Fighter:
	var best: Fighter = null
	var best_score := INF
	for other in arena.fighters:
		if other.slot == me.slot or not other.alive:
			continue
		var score := me.position().distance_to(other.position())
		if not arena.court.clear_line(me.position(), other.position()):
			score += 2000.0
		if score < best_score:
			best_score = score
			best = other
	return best


# The eight-way step closest to the wanted direction that the court lets it take; turning left or right of a pillar.
func _free_direction(court: Court, me: Fighter, wanted: Vector2) -> Vector2i:
	var first := Vector2i(axis_sign(wanted.x, wanted.y), axis_sign(wanted.y, wanted.x))
	var tries: Array[Vector2i] = [first, Vector2i(first.x, 0), Vector2i(0, first.y)]
	tries.append(Vector2i(-first.y, first.x) * _circle)
	tries.append(Vector2i(first.y, -first.x) * _circle)
	for d in tries:
		if d == Vector2i.ZERO:
			continue
		if court.box_free(me.x + d.x * Sim.SPEED, me.y + d.y * Sim.SPEED):
			return d
	return Vector2i.ZERO


# -1, 0 or 1 for one axis of a direction: 0 when the axis is under half the other, so moves are eight-way.
static func axis_sign(value: float, other: float) -> int:
	if is_zero_approx(value) or absf(value) < absf(other) * 0.5:
		return 0
	return 1 if value > 0.0 else -1
