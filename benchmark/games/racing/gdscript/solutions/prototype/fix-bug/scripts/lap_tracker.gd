class_name LapTracker
extends RefCounted
## Counts one car's laps: the gates must be crossed in order, each in the direction of travel, and a lap is done when
## the start line is crossed after the last gate. A gate crossed out of turn counts for nothing, so cutting across the
## grass past a checkpoint never shortens a lap. Lap times are in ticks, from the start (lap 1) or the last line.

enum Crossing { NONE, GATE, LAP }

## The gate to cross next; 0 is the start line.
var next_gate := 0
## Whether the car has crossed the start line once: the grid is behind it.
var armed := false
var laps := 0
var lap_start_tick := 0
var lap_times: Array[int] = []
## The fastest lap so far in ticks, -1 before the first.
var best_lap := -1


func update(track: Track, from: Vector2, to: Vector2, tick: int) -> Crossing:
	if not track.crosses_gate(next_gate, from, to):
		return Crossing.NONE
	if next_gate != 0:
		next_gate = (next_gate + 1) % track.gate_count()
		return Crossing.GATE
	next_gate = 1 % track.gate_count()
	if not armed:
		armed = true
		return Crossing.GATE
	var time := tick - lap_start_tick
	lap_times.append(time)
	lap_start_tick = tick
	laps += 1
	if best_lap < 0 or time < best_lap:
		best_lap = time
	return Crossing.LAP


## How many gates of the lap in progress are behind the car (the start line counts once armed).
func gates_passed(track: Track) -> int:
	if not armed:
		return 0
	return track.gate_count() if next_gate == 0 else next_gate


func last_lap() -> int:
	return lap_times[lap_times.size() - 1] if not lap_times.is_empty() else -1
