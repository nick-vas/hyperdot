extends Node2D
## The busiest field the game can show, for the kit's bench: a wide maze of towers, a swarm of pests kept at
## PESTS on the field and every shot in the air, drawn by the game's own Field.
## hyperdot.ps1 bench -Scene res://bench/swarm.tscn -BudgetMs 16.6

const PESTS := 200
const ROWS := [
	"................",
	"................",
	"................",
	"................",
	"S..............G",
	"................",
	"................",
	"................",
	"................",
]

var battle: Battle

@onready var _field: Node2D = $Field


func _ready() -> void:
	battle = Battle.custom(Catalog.from_files(), ROWS, 100000, 100000, [], 1, "swarm")
	# Walls with a gap at alternate ends: the longest way across the field, lined with towers on both sides.
	var kinds: Array[String] = ["thorn", "puff", "acorn"]
	var n := 0
	for x in range(2, 15, 3):
		for y in 9:
			var gap := 8 if (x - 2) % 6 == 0 else 0
			if y != gap and battle.place(kinds[n % kinds.size()], Vector2i(x, y)):
				n += 1
	_field.show_battle(battle)


func _physics_process(_delta: float) -> void:
	while battle.enemies.size() < PESTS:
		var pest := battle.spawn_at(["aphid", "beetle", "moth"][battle.enemies.size() % 3], battle.map.gate)
		pest.hp = 1000000
	battle.step()
	_field.queue_redraw()
