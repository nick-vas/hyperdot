class_name Race
extends RefCounted
## One race on a track: the cars, their drivers and lap trackers, the finishing order and the player's ghost. Car 0 is
## the player's: driven by the input given to step(), or by its own driver when it has one (the bot, or after the
## flag). Every tick steps the cars in order with quantised inputs, so a race replays exactly from its grid and inputs.

signal lap_completed(car: int, lap: int, ticks: int)
signal car_finished(car: int, place: int)

var track: Track
var cars: Array[Car] = []
var trackers: Array[LapTracker] = []
## An AiDriver for each car, or null for the player's.
var drivers: Array = []
var tick := 0
var rate := 60
## Car indices in the order they took the flag.
var finish_order: Array[int] = []
## The fastest lap of car 0 as inputs, and the lap being recorded now.
var best_ghost: Ghost
var ghost: Ghost


## drivers: car 0 first (null when the player drives it); the grid puts car 0 last and the others in the given order.
func _init(race_track: Track, car_drivers: Array, ticks_per_second := 60) -> void:
	track = race_track
	drivers = car_drivers.duplicate()
	rate = ticks_per_second
	var count := drivers.size()
	for i in count:
		var slot := count - 1 if i == 0 else i - 1
		var car := Car.at(track.grid_slot(slot))
		car.index = track.nearest(car.position)
		cars.append(car)
		trackers.append(LapTracker.new())
	ghost = Ghost.new(cars[0].state(), rate)


func step(player_input := Vector2.ZERO) -> void:
	tick += 1
	var dt := 1.0 / rate
	for i in cars.size():
		var car := cars[i]
		var driver: AiDriver = drivers[i]
		var input := player_input
		if driver != null:
			input = driver.decide(car, track)
		var throttle := input.x
		var steer := Ghost.quantize(input.y)
		if i == 0:
			ghost.record(throttle, steer)
		var from := car.position
		car.step(throttle, steer, dt, track.is_on_road(car.position, car.index))
		car.index = track.nearest(car.position, car.index)
		if trackers[i].update(track, from, car.position, tick) == LapTracker.Crossing.LAP:
			_lap_done(i)


func _lap_done(i: int) -> void:
	var tracker := trackers[i]
	if i == 0:
		if best_ghost == null or tracker.last_lap() < best_ghost.ticks():
			best_ghost = ghost
		ghost = Ghost.new(cars[0].state(), rate)
	lap_completed.emit(i, tracker.laps, tracker.last_lap())
	if tracker.laps == track.laps and not finish_order.has(i):
		finish_order.append(i)
		car_finished.emit(i, finish_order.size())


func is_finished(i: int) -> bool:
	return finish_order.has(i)


## Car indices from first to last: those that took the flag in that order, then by laps done, gates passed in the lap
## and the distance left to the next gate; level cars by index.
func standings() -> Array[int]:
	var order: Array[int] = []
	for i in cars.size():
		order.append(i)
	order.sort_custom(_ahead)
	return order


## 1 for the leader.
func position_of(i: int) -> int:
	return standings().find(i) + 1


func _ahead(a: int, b: int) -> bool:
	var fa := finish_order.find(a)
	var fb := finish_order.find(b)
	if fa >= 0 or fb >= 0:
		if fa < 0 or fb < 0:
			return fa >= 0
		return fa < fb
	var ta := trackers[a]
	var tb := trackers[b]
	if ta.laps != tb.laps:
		return ta.laps > tb.laps
	var ga := ta.gates_passed(track)
	var gb := tb.gates_passed(track)
	if ga != gb:
		return ga > gb
	var da := _to_next_gate(a)
	var db := _to_next_gate(b)
	if not is_equal_approx(da, db):
		return da < db
	return a < b


## How far car i has to go along the track to its next gate.
func _to_next_gate(i: int) -> float:
	var car := cars[i]
	var gate_at := track.lengths[track.gate_points[trackers[i].next_gate]]
	return fposmod(gate_at - track.distance_along(car.position, car.index), track.length())


## A time in milliseconds as minutes, seconds and thousandths: 83456 is 1:23.456.
static func format_ms(ms: int) -> String:
	return "%d:%02d.%03d" % [ms / 60000, (ms / 1000) % 60, ms % 1000]
