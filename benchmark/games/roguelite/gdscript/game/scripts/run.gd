class_name Run
extends RefCounted
## One descent: its seed, the floor it is on, and what the wick carries from floor to floor. Every floor of a run is
## generated from the run's seed and the floor's number alone, so a saved run is these few numbers.

var seed_value := 0
var floor_number := 1
var hp := 5
var max_hp := 5
## Embers gathered so far in this run; Meta banks them when it ends.
var embers := 0


func _init(run_seed := 0, wick_hp := 5) -> void:
	seed_value = run_seed
	hp = wick_hp
	max_hp = wick_hp


## The seed of the current floor: its dungeon and its enemies' choices.
func floor_seed() -> int:
	return seed_value * 1009 + floor_number


func to_dict() -> Dictionary:
	return {"seed": seed_value, "floor": floor_number, "hp": hp, "max_hp": max_hp, "embers": embers}


static func from_dict(data: Dictionary) -> Run:
	var run := Run.new(int(data.get("seed", 0)), int(data.get("max_hp", 5)))
	run.floor_number = maxi(1, int(data.get("floor", 1)))
	run.hp = clampi(int(data.get("hp", run.max_hp)), 1, run.max_hp)
	run.embers = maxi(0, int(data.get("embers", 0)))
	return run
