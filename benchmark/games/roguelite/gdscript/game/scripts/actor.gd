class_name Actor
extends RefCounted
## One creature on a floor's grid: the wick (the player) or an enemy. Plain data that World moves one cell at a time;
## the game only draws it, sliding it from the cell it left to the one it stands on.

var kind := ""
var cell := Vector2i.ZERO
## The cell it left on its last step and the tick it stepped, for the game's slide.
var from_cell := Vector2i.ZERO
var moved_at := -1000
var hp := 1
var max_hp := 1
var damage := 1
## Ticks between two steps, and between two blows.
var move_ticks := 10
var attack_ticks := 40
## How far it sees, in cells.
var sight := 5
## What snuffing it gives the wick's run.
var embers := 0
var move_cooldown := 0
var attack_cooldown := 0
var facing := Vector2i.DOWN
## Ticks an enemy goes on hunting the wick after losing sight of it; 0 while it wanders.
var alert := 0
## Ticks the wick cannot be hurt again after a hurt.
var mercy := 0
## The tick it was last struck, for the game's flash.
var hit_at := -1000


## An enemy of a kind of data/enemies.json, standing on a cell.
static func from_kind(stats: Dictionary, at: Vector2i) -> Actor:
	var actor := Actor.new()
	actor.kind = str(stats.get("id", ""))
	actor.cell = at
	actor.from_cell = at
	actor.hp = int(stats.get("hp", 1))
	actor.max_hp = actor.hp
	actor.damage = int(stats.get("damage", 1))
	actor.move_ticks = int(stats.get("move_ticks", 10))
	actor.attack_ticks = int(stats.get("attack_ticks", 40))
	actor.sight = int(stats.get("sight", 5))
	actor.embers = int(stats.get("embers", 1))
	return actor
