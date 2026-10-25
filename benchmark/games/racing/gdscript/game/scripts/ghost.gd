class_name Ghost
extends RefCounted
## A lap as its inputs: the car's state where the lap began and the throttle and steering of every tick after it, in
## hundredths. Played back through Car on the same track, it drives the lap again exactly, because Race quantises every
## input before a car uses it: what the ghost keeps is what the car was given. A recording is small (two numbers a
## tick) and is saved with the best lap.

var start := {}
## The tick rate it was recorded at: a ghost plays back only at the same rate.
var rate := 60
var throttles := PackedInt32Array()
var steers := PackedInt32Array()


func _init(start_state := {}, ticks_per_second := 60) -> void:
	start = start_state.duplicate()
	rate = ticks_per_second


## An input as the car gets it: hundredths, so a recording holds it exactly.
static func quantize(value: float) -> float:
	return roundi(clampf(value, -1.0, 1.0) * 100.0) / 100.0


func record(throttle: float, steer: float) -> void:
	throttles.append(roundi(clampf(throttle, -1.0, 1.0) * 100.0))
	steers.append(roundi(clampf(steer, -1.0, 1.0) * 100.0))


func ticks() -> int:
	return throttles.size()


func input_at(tick: int) -> Vector2:
	if tick < 0 or tick >= throttles.size():
		return Vector2.ZERO
	return Vector2(throttles[tick] / 100.0, steers[tick] / 100.0)


## A car at the lap's start, to step with input_at(0), input_at(1)...
func start_car() -> Car:
	return Car.at(start)


## Steps a car through the recording on a track and returns where it was after each tick.
func replay(track: Track) -> PackedVector2Array:
	var car := start_car()
	car.index = track.nearest(car.position)
	var out := PackedVector2Array()
	for t in ticks():
		var input := input_at(t)
		car.step(input.x, input.y, 1.0 / rate, track.is_on_road(car.position, car.index))
		car.index = track.nearest(car.position, car.index)
		out.append(car.position)
	return out


func to_dict() -> Dictionary:
	var at: Vector2 = start.get("position", Vector2.ZERO)
	return {
		"rate": rate,
		"start": {"x": at.x, "y": at.y, "heading": float(start.get("heading", 0.0)), "speed": float(start.get("speed", 0.0))},
		"throttle": Array(throttles),
		"steer": Array(steers),
	}


## A ghost from saved data; null when it is damaged.
static func from_dict(data: Variant) -> Ghost:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var raw_start: Variant = data.get("start", {})
	var raw_throttle: Variant = data.get("throttle", [])
	var raw_steer: Variant = data.get("steer", [])
	if typeof(raw_start) != TYPE_DICTIONARY or typeof(raw_throttle) != TYPE_ARRAY or typeof(raw_steer) != TYPE_ARRAY or raw_throttle.size() != raw_steer.size():
		return null
	var state := {
		"position": Vector2(float(raw_start.get("x", 0.0)), float(raw_start.get("y", 0.0))),
		"heading": float(raw_start.get("heading", 0.0)),
		"speed": float(raw_start.get("speed", 0.0)),
	}
	var ghost := Ghost.new(state, int(data.get("rate", 60)))
	for value: Variant in raw_throttle:
		ghost.throttles.append(int(value))
	for value: Variant in raw_steer:
		ghost.steers.append(int(value))
	return ghost
