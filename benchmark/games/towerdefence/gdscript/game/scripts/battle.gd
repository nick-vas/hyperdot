class_name Battle
extends RefCounted
## One map's battle, engine-light: the sap (gold), the seeds left in the store (lives), the towers, the pests, the shots
## in the air and the waves. step() advances it one tick, 60 to a second of play; the game node calls it and draws what
## it holds, so tests and the bot play whole maps without a scene.
##
## A tick runs, in this order: the break before the next wave, spawns, pests walking, towers firing, shots flying, and
## the end of the wave.

signal wave_started(number: int)
signal wave_cleared(number: int, bonus: int)
signal tower_placed(cell: Vector2i)
signal tower_upgraded(cell: Vector2i)
signal tower_sold(cell: Vector2i, refund: int)
signal shot_fired(cell: Vector2i)
signal enemy_killed(enemy: Enemy)
signal enemy_leaked(enemy: Enemy)
signal battle_over(won: bool)

enum Phase { BUILD, WAVE, WON, LOST }
const PHASE_NAMES := ["Build", "Wave", "Won", "Lost"]
const TICKS_PER_SECOND := 60
## Ticks between the end of a wave (or the start of the map) and the next wave, unless it is called early.
const BREAK_TICKS := 600
## What selling gives back, of everything the tower cost.
const SELL_SHARE := 0.7
## A tower with nothing in range looks again this many ticks later.
const IDLE_TICKS := 4
## Each pest's speed varies by up to this share, from the battle's own generator.
const SPEED_JITTER := 0.08

var catalog: Catalog
var map: PathMap
var map_id := ""
var gold := 0
var lives := 0
var start_lives := 0
## The wave under way, or the last one cleared; 0 before the first.
var wave := 0
var waves: Array = []
var phase := Phase.BUILD
var ticks := 0
var break_left := BREAK_TICKS
## Cell -> { "id", "level", "cooldown" }, in the order they were built.
var towers := {}
var enemies: Array[Enemy] = []
## Each { "pos", "aim", "target", "damage", "speed", "splash", "slow", "tower" }.
var shots: Array[Dictionary] = []
## Every distance test towers made looking for a target: the performance tests read it.
var range_checks := 0
var kills := 0
var leaks := 0

var _spawns: Array[Dictionary] = []
var _wave_tick := 0
var _next_uid := 1
var _rng := RandomNumberGenerator.new()


## A battle on one of the catalog's maps, its pests' speeds drawn from seed_value.
static func create(game_catalog: Catalog, id: String, seed_value: int) -> Battle:
	var row: Dictionary = {}
	for entry: Dictionary in game_catalog.maps:
		if entry.id == id:
			row = entry
	if row.is_empty():
		push_error("Battle: there is no map %s" % id)
		return null
	return custom(game_catalog, row.rows, int(row.gold), int(row.lives), game_catalog.waves_for(id), seed_value, id)


## A battle on any rows of text (PathMap.from_rows), for tests and the bench.
static func custom(game_catalog: Catalog, rows: Array, start_gold: int, start_lives_count: int, wave_list: Array, seed_value := 1, id := "custom") -> Battle:
	var battle := Battle.new()
	battle.catalog = game_catalog
	battle.map = PathMap.from_rows(rows)
	battle.map_id = id
	battle.gold = start_gold
	battle.lives = start_lives_count
	battle.start_lives = start_lives_count
	battle.waves = wave_list
	battle._rng.seed = seed_value
	return battle


func phase_name() -> String:
	return PHASE_NAMES[phase]


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


# ---- Building ----

## Whether a tower of this kind may go on this cell now: enough sap, an open cell no pest stands on or is heading to,
## and the gate and every pest still with a way to the store.
func can_place(id: String, cell: Vector2i) -> bool:
	if is_over() or not catalog.has_tower(id) or gold < catalog.cost(id):
		return false
	if not map.is_buildable(cell) or towers.has(cell) or _occupied(cell):
		return false
	return not map.blocks(cell, _enemy_targets())


func place(id: String, cell: Vector2i) -> bool:
	if not can_place(id, cell):
		return false
	gold -= catalog.cost(id)
	towers[cell] = {"id": id, "level": 1, "cooldown": 0}
	map.set_tower(cell, true)
	_repath()
	tower_placed.emit(cell)
	return true


func can_upgrade(cell: Vector2i) -> bool:
	if is_over() or not towers.has(cell):
		return false
	var tower: Dictionary = towers[cell]
	var price := catalog.upgrade_cost(tower.id, tower.level + 1)
	return tower.level < catalog.max_level(tower.id) and gold >= price


func upgrade(cell: Vector2i) -> bool:
	if not can_upgrade(cell):
		return false
	var tower: Dictionary = towers[cell]
	gold -= catalog.upgrade_cost(tower.id, tower.level + 1)
	tower.level += 1
	tower_upgraded.emit(cell)
	return true


## What selling the tower on this cell gives back: SELL_SHARE of its cost and of every upgrade bought for it.
func refund(cell: Vector2i) -> int:
	if not towers.has(cell):
		return 0
	var tower: Dictionary = towers[cell]
	var value := catalog.cost(tower.id)
	for level in range(2, tower.level + 1):
		value += catalog.upgrade_cost(tower.id, level)
	return floori(value * SELL_SHARE)


## Sells the tower on this cell; the pests take the shorter ways it opens. Returns the sap given back.
func sell(cell: Vector2i) -> int:
	if is_over() or not towers.has(cell):
		return 0
	var back := refund(cell)
	gold += back
	towers.erase(cell)
	map.set_tower(cell, false)
	_repath()
	tower_sold.emit(cell, back)
	return back


## A pest stands on the cell or is heading to it.
func _occupied(cell: Vector2i) -> bool:
	for enemy in enemies:
		if enemy.cell() == cell or enemy.target() == cell:
			return true
	return false


func _enemy_targets() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for enemy in enemies:
		cells.append(enemy.target())
	return cells


## Every pest takes the shortest way from the cell it is heading to, as the map now stands.
func _repath() -> void:
	for enemy in enemies:
		enemy.path = map.path_from(enemy.target())


# ---- Waves ----

## Starts the next wave now, before its break is over; false when one is under way or none is left.
func start_wave() -> bool:
	if phase != Phase.BUILD or wave >= waves.size():
		return false
	wave += 1
	phase = Phase.WAVE
	_wave_tick = ticks
	_spawns.clear()
	var order := 0
	for group: Dictionary in waves[wave - 1].groups:
		for i in int(group.count):
			_spawns.append({"tick": int(group.delay) + i * int(group.gap), "enemy": str(group.enemy), "order": order})
			order += 1
	_spawns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.tick < b.tick or (a.tick == b.tick and a.order < b.order))
	print("[Wave] %s wave %d of %d" % [map_id, wave, waves.size()])
	wave_started.emit(wave)
	return true


## Puts a pest on a cell at once, outside any wave's schedule: for tests and the bench.
func spawn_at(id: String, cell: Vector2i) -> Enemy:
	_spawn(id)
	var enemy := enemies[-1]
	enemy.pos = Enemy.centre(cell)
	enemy.path = map.path_from(cell).slice(1)
	return enemy


## The pests of the wave still to come.
func pending() -> int:
	return _spawns.size()


func step() -> void:
	if is_over():
		return
	ticks += 1
	if phase == Phase.BUILD:
		break_left -= 1
		if break_left <= 0:
			start_wave()
	_spawn_due()
	_walk()
	if is_over():
		return
	_fire()
	_fly()
	if phase == Phase.WAVE and _spawns.is_empty() and enemies.is_empty():
		_clear_wave()


func _spawn_due() -> void:
	while not _spawns.is_empty() and int(_spawns[0].tick) <= ticks - _wave_tick:
		var due: Dictionary = _spawns.pop_front()
		_spawn(str(due.enemy))


func _spawn(id: String) -> void:
	var row: Dictionary = catalog.enemies[id]
	var enemy := Enemy.new()
	enemy.uid = _next_uid
	_next_uid += 1
	enemy.id = id
	enemy.hp = int(row.hp)
	enemy.max_hp = enemy.hp
	enemy.speed = float(row.speed) * (1.0 + _rng.randf_range(-SPEED_JITTER, SPEED_JITTER)) / TICKS_PER_SECOND
	enemy.reward = int(row.reward)
	enemy.leak = int(row.leak)
	enemy.pos = Enemy.centre(map.gate)
	enemy.path = map.route.slice(1)
	enemies.append(enemy)


func _walk() -> void:
	var arrived: Array[Enemy] = []
	for enemy in enemies:
		var left := enemy.pace()
		if enemy.slow_ticks > 0:
			enemy.slow_ticks -= 1
		while left > 0.0 and not enemy.path.is_empty():
			var next: Vector2i = enemy.path[0]
			# A pest never walks into a tower: it waits until it has a way.
			if not map.is_open(next):
				break
			var goal := Enemy.centre(next)
			var gap := enemy.pos.distance_to(goal)
			if gap <= left:
				enemy.pos = goal
				left -= gap
				enemy.path.pop_front()
			else:
				enemy.pos += (goal - enemy.pos) / gap * left
				left = 0.0
		if enemy.path.is_empty() and enemy.cell() == map.store:
			arrived.append(enemy)
	for enemy in arrived:
		_leak(enemy)


func _leak(enemy: Enemy) -> void:
	enemy.alive = false
	enemies.erase(enemy)
	leaks += 1
	lives = maxi(lives - enemy.leak, 0)
	enemy_leaked.emit(enemy)
	if lives == 0:
		_end(false)


func _fire() -> void:
	for cell: Vector2i in towers:
		var tower: Dictionary = towers[cell]
		if tower.cooldown > 0:
			tower.cooldown -= 1
			if tower.cooldown > 0:
				continue
		var stats := catalog.stats(tower.id, tower.level)
		var enemy := _target_for(cell, float(stats["range"]))
		if enemy == null:
			tower.cooldown = IDLE_TICKS
			continue
		var from := Enemy.centre(cell)
		shots.append({
			"pos": from, "aim": enemy.pos, "target": enemy, "damage": int(stats.damage),
			"speed": float(stats.shot_speed) / TICKS_PER_SECOND, "splash": float(stats.splash), "slow": float(stats.slow),
			"tower": str(tower.id),
		})
		tower.cooldown = int(stats.reload)
		shot_fired.emit(cell)


## The pest in range that is closest to the store along its way: towers shoot the one about to leak first.
func _target_for(cell: Vector2i, reach: float) -> Enemy:
	var from := Enemy.centre(cell)
	var best: Enemy = null
	var best_left := INF
	for enemy in enemies:
		range_checks += 1
		if enemy.pos.distance_squared_to(from) > reach * reach:
			continue
		var left := enemy.remaining()
		if left < best_left:
			best = enemy
			best_left = left
	return best


func _fly() -> void:
	var landed: Array[Dictionary] = []
	for shot in shots:
		var target: Enemy = shot.target
		if target.alive:
			shot.aim = target.pos
		var pos: Vector2 = shot.pos
		var aim: Vector2 = shot.aim
		var gap := pos.distance_to(aim)
		if gap <= float(shot.speed):
			shot.pos = aim
			landed.append(shot)
		else:
			shot.pos = pos + (aim - pos) / gap * float(shot.speed)
	for shot in landed:
		shots.erase(shot)
		_hit(shot)


func _hit(shot: Dictionary) -> void:
	var splash := float(shot.splash)
	if splash <= 0.0:
		var target: Enemy = shot.target
		if target.alive:
			_wound(target, int(shot.damage), float(shot.slow))
		return
	var aim: Vector2 = shot.aim
	for enemy in enemies.duplicate():
		if enemy.pos.distance_to(aim) <= splash:
			_wound(enemy, int(shot.damage), float(shot.slow))


func _wound(enemy: Enemy, damage: int, slow: float) -> void:
	enemy.hp -= damage
	if slow > 0.0:
		enemy.slow = slow
		enemy.slow_ticks = Enemy.SLOW_TICKS
	if enemy.hp <= 0 and enemy.alive:
		enemy.alive = false
		enemies.erase(enemy)
		kills += 1
		gold += enemy.reward
		enemy_killed.emit(enemy)


func _clear_wave() -> void:
	var bonus := int(waves[wave - 1].bonus)
	gold += bonus
	print("[Wave] %s wave %d cleared, bonus %d" % [map_id, wave, bonus])
	wave_cleared.emit(wave, bonus)
	if wave >= waves.size():
		_end(true)
		return
	phase = Phase.BUILD
	break_left = BREAK_TICKS


func _end(won: bool) -> void:
	phase = Phase.WON if won else Phase.LOST
	shots.clear()
	battle_over.emit(won)
