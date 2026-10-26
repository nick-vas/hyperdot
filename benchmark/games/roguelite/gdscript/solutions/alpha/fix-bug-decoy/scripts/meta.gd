class_name Meta
extends RefCounted
## What outlasts a run, kept in the save's "meta": embers banked over every run, vigor bought with them at the shrine
## (each level one more hp for the wick), the deepest floor reached and the runs played.

const BASE_HP := 5
const VIGOR_MAX := 3


static func defaults() -> Dictionary:
	return {"embers": 0, "vigor": 0, "best_floor": 0, "runs": 0}


static func max_hp(save: Dictionary) -> int:
	return BASE_HP + int(save.meta.vigor)


## Embers the next level of vigor costs: 5, 10, then 15.
static func vigor_cost(level: int) -> int:
	return 5 * (level + 1)


## Spends banked embers on a level of vigor; false when there are too few or vigor is full.
static func buy_vigor(save: Dictionary) -> bool:
	var meta: Dictionary = save.meta
	var level := int(meta.vigor)
	if level >= VIGOR_MAX or int(meta.embers) < vigor_cost(level):
		return false
	meta.embers = int(meta.embers) - vigor_cost(level)
	meta.vigor = level + 1
	return true


## A run ended on floor_reached: its embers join the bank (half of them, rounded down, after a death).
static func bank(save: Dictionary, run_embers: int, floor_reached: int, won: bool) -> void:
	var meta: Dictionary = save.meta
	if won:
		meta.embers = int(meta.embers) + run_embers
	else:
		meta.embers = run_embers / 2
	meta.best_floor = maxi(int(meta.best_floor), floor_reached)
	meta.runs = int(meta.runs) + 1
