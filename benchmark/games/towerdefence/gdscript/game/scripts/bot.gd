class_name Bot
extends RefCounted
## A player that builds by rule, for --autoplay and the balance tests: towers in a fixed order, each on the cell where
## the route it leaves passes closest to it most often (so it builds a maze), then upgrades, the lowest level first. It
## calls the next wave as soon as it has nothing to buy. Deterministic: the same battle gets the same build.

const ORDER: Array[String] = ["thorn", "thorn", "puff", "acorn"]
const MAX_TOWERS := 10


## One decision: builds or upgrades at most one thing, or calls the next wave.
func act(battle: Battle) -> void:
	if battle.is_over():
		return
	if battle.towers.size() < MAX_TOWERS:
		var id: String = ORDER[battle.towers.size() % ORDER.size()]
		if battle.gold >= battle.catalog.cost(id):
			for cell in _best_cells(battle, id):
				if battle.place(id, cell):
					return
		else:
			_call_wave(battle)
			return
	var lowest := Vector2i(-1, -1)
	for cell: Vector2i in battle.towers:
		var tower: Dictionary = battle.towers[cell]
		if tower.level < battle.catalog.max_level(tower.id) and (lowest.x < 0 or tower.level < battle.towers[lowest].level):
			lowest = cell
	if lowest.x >= 0 and battle.upgrade(lowest):
		return
	_call_wave(battle)


func _call_wave(battle: Battle) -> void:
	if battle.phase == Battle.Phase.BUILD:
		battle.start_wave()


## The cells a tower could go on, best first: how many cells of the route it would leave lie within its range.
func _best_cells(battle: Battle, id: String) -> Array[Vector2i]:
	var reach := float(battle.catalog.stats(id, 1)["range"])
	var scored: Array[Dictionary] = []
	for y in battle.map.size.y:
		for x in battle.map.size.x:
			var cell := Vector2i(x, y)
			if not battle.map.is_buildable(cell) or not _near_route(battle.map.route, cell, reach):
				continue
			var route := battle.map.preview_route(cell)
			if route.is_empty():
				continue
			var covered := 0
			for step in route:
				if Enemy.centre(step).distance_squared_to(Enemy.centre(cell)) <= reach * reach:
					covered += 1
			scored.append({"cell": cell, "score": covered, "order": scored.size()})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score or (a.score == b.score and a.order < b.order))
	var cells: Array[Vector2i] = []
	for entry in scored:
		cells.append(entry.cell)
	return cells


func _near_route(route: Array[Vector2i], cell: Vector2i, reach: float) -> bool:
	for step in route:
		if Enemy.centre(step).distance_squared_to(Enemy.centre(cell)) <= reach * reach:
			return true
	return false


## Plays a battle to its end with this bot, for tests: true when it was won. Gives up after max_ticks.
static func play(battle: Battle, max_ticks := 60000) -> bool:
	var bot := Bot.new()
	while not battle.is_over() and battle.ticks < max_ticks:
		bot.act(battle)
		battle.step()
	return battle.phase == Battle.Phase.WON


## Plays a battle to its end with no tower at all.
static func idle(battle: Battle, max_ticks := 60000) -> bool:
	while not battle.is_over() and battle.ticks < max_ticks:
		battle.start_wave()
		battle.step()
	return battle.phase == Battle.Phase.WON
