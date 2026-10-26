class_name World
extends RefCounted
## One floor being played: the dungeon, the wick and the enemies, stepped one tick at a time by step(). The rules and
## the enemies' minds live here, not in nodes, so tests and the bot play whole floors without a scene, and a floor plays
## the same from the same seed and the same inputs.
##
## Enemies wander until they see the wick (within their sight, no wall in between), then hunt it down the floor's one
## distance field, which is searched again only when the wick changes cell: a hundred hunters cost one search, not a
## hundred. Next to the wick (not diagonally) an enemy strikes, after a wind-up the wick can see coming.

signal enemy_hit(enemy: Actor)
signal enemy_snuffed(enemy: Actor)
signal wick_hurt(amount: int)
## The last enemy is gone: the stairs down are open.
signal stairs_opened

const WICK_MOVE_TICKS := 6
const WICK_ATTACK_TICKS := 14
## Ticks after a hurt during which the wick cannot be hurt again.
const MERCY_TICKS := 30
## Ticks an enemy goes on hunting after it loses sight of the wick.
const MEMORY_TICKS := 90
## Ticks an enemy that has just come next to the wick waits before its first blow.
const WINDUP_TICKS := 30
## How long a swarm keeps hunting: for ever, in practice.
const SWARM_ALERT := 1 << 30

var dungeon: Dungeon
var wick: Actor
var enemies: Array[Actor] = []
var tick := 0
## Embers gathered on this floor.
var embers := 0
var stairs_open := false
## The wick stood on the open stairs: the floor is cleared.
var done := false
## How many distance fields the enemies' hunting has searched, for the performance test.
var path_searches := 0

var _occupied := {}
var _field := PackedInt32Array()
var _field_from := Vector2i(-1, -1)
## The enemies' own stream: wandering, and where a swarm appears. Not the generator's, so a change to how enemies
## wander never moves a room.
var _rng := RandomNumberGenerator.new()


## kinds: enemy id -> stats (Floors.kinds). The wick starts on the dungeon's start with hp of max_hp.
static func create(floor_dungeon: Dungeon, kinds: Dictionary, seed_value: int, hp: int, max_hp: int) -> World:
	var world := World.new()
	world.dungeon = floor_dungeon
	world._rng.seed = seed_value * 31 + 7
	world.wick = Actor.new()
	world.wick.kind = "wick"
	world.wick.cell = floor_dungeon.start
	world.wick.from_cell = floor_dungeon.start
	world.wick.max_hp = max_hp
	world.wick.hp = clampi(hp, 1, max_hp)
	world.wick.move_ticks = WICK_MOVE_TICKS
	world.wick.attack_ticks = WICK_ATTACK_TICKS
	world._occupied[world.wick.cell] = world.wick
	for spawn in floor_dungeon.spawns:
		world.add_enemy(Actor.from_kind(kinds.get(spawn.kind, {"id": spawn.kind}), spawn.cell))
	world.stairs_open = world.enemies.is_empty()
	return world


func add_enemy(enemy: Actor) -> void:
	enemies.append(enemy)
	_occupied[enemy.cell] = enemy


## count enemies of a kind, already hunting, on free floor cells at least 6 steps from the wick: the load for bench.
func add_swarm(count: int, stats: Dictionary) -> void:
	var field := dungeon.distance_field(wick.cell)
	var cells: Array[Vector2i] = []
	for y in dungeon.height:
		for x in dungeon.width:
			var cell := Vector2i(x, y)
			if field[dungeon.index(cell)] >= 6 and not _occupied.has(cell) and cell != dungeon.stairs:
				cells.append(cell)
	for i in mini(count, cells.size()):
		var pick := _rng.randi_range(i, cells.size() - 1)
		var cell := cells[pick]
		cells[pick] = cells[i]
		var bat := Actor.from_kind(stats, cell)
		bat.alert = SWARM_ALERT
		add_enemy(bat)
	stairs_open = enemies.is_empty()


## One tick: the wick acts on its input (move: one of Dungeon.DIRS or zero), then every enemy thinks.
func step(move: Vector2i, attack: bool) -> void:
	tick += 1
	wick.move_cooldown = maxi(wick.move_cooldown - 1, 0)
	wick.attack_cooldown = maxi(wick.attack_cooldown - 1, 0)
	wick.mercy = maxi(wick.mercy - 1, 0)
	if wick.hp <= 0 or done:
		return
	if attack and wick.attack_cooldown == 0:
		_swing()
	if move != Vector2i.ZERO and wick.move_cooldown == 0:
		wick.facing = move
		if _can_enter(wick.cell + move):
			_move(wick, wick.cell + move)
			wick.move_cooldown = WICK_MOVE_TICKS
	if stairs_open and wick.cell == dungeon.stairs:
		done = true
		return
	_refresh_field()
	for enemy in enemies.duplicate():
		_think(enemy)
	# An enemy that wandered into the rock can never be reached: it is snuffed, so the floor can still be cleared.
	for enemy in enemies.duplicate():
		if not dungeon.is_floor(enemy.cell):
			_snuff(enemy)


func _think(enemy: Actor) -> void:
	enemy.move_cooldown = maxi(enemy.move_cooldown - 1, 0)
	enemy.attack_cooldown = maxi(enemy.attack_cooldown - 1, 0)
	if sees(enemy):
		enemy.alert = maxi(enemy.alert, MEMORY_TICKS)
	elif enemy.alert > 0:
		enemy.alert -= 1
	if adjacent(enemy.cell, wick.cell):
		if enemy.attack_cooldown == 0:
			hurt_wick(enemy.damage)
			enemy.attack_cooldown = enemy.attack_ticks
		return
	# Away from the wick it is never ready to strike at once: the wind-up starts when it arrives.
	enemy.attack_cooldown = maxi(enemy.attack_cooldown, WINDUP_TICKS)
	if enemy.move_cooldown > 0:
		return
	enemy.move_cooldown = enemy.move_ticks
	if enemy.alert > 0:
		_hunt(enemy)
	else:
		_wander(enemy)


## One step down the distance field towards the wick, to the free neighbour nearest it.
func _hunt(enemy: Actor) -> void:
	var field := _field
	var here := field[dungeon.index(enemy.cell)] if dungeon.in_bounds(enemy.cell) else -1
	var best := enemy.cell
	var best_distance := here if here >= 0 else 1 << 30
	for dir in Dungeon.DIRS:
		var next := enemy.cell + dir
		if not _can_enter(next):
			continue
		var distance := field[dungeon.index(next)]
		if distance >= 0 and distance < best_distance:
			best_distance = distance
			best = next
	if best != enemy.cell:
		_move(enemy, best)


## A step in a random direction, or none; walls and other creatures stop it.
func _wander(enemy: Actor) -> void:
	var roll := _rng.randi_range(0, 5)
	if roll >= Dungeon.DIRS.size():
		return
	var next := enemy.cell + Dungeon.DIRS[roll]
	if dungeon.in_bounds(next) and not _occupied.has(next):
		_move(enemy, next)


## The field the hunters follow, searched again only when the wick has moved.
func _refresh_field() -> void:
	if wick.cell != _field_from:
		_field = _search(wick.cell)
		_field_from = wick.cell


func _search(from: Vector2i) -> PackedInt32Array:
	path_searches += 1
	return dungeon.distance_field(from)


## Whether an enemy sees the wick: within its sight (a circle) and no wall on the line between them.
func sees(enemy: Actor) -> bool:
	var gap := wick.cell - enemy.cell
	if gap.x * gap.x + gap.y * gap.y > enemy.sight * enemy.sight:
		return false
	return dungeon.line_clear(enemy.cell, wick.cell)


## Side by side, not diagonally.
static func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _can_enter(cell: Vector2i) -> bool:
	return dungeon.is_floor(cell) and not _occupied.has(cell)


func _move(actor: Actor, to: Vector2i) -> void:
	_occupied.erase(actor.cell)
	actor.from_cell = actor.cell
	actor.moved_at = tick
	actor.cell = to
	_occupied[to] = actor


func enemy_at(cell: Vector2i) -> Actor:
	var actor: Actor = _occupied.get(cell)
	return actor if actor != null and actor != wick else null


## The first enemy beside a cell, in the order of Dungeon.DIRS; null when there is none.
func enemy_beside(cell: Vector2i) -> Actor:
	for dir in Dungeon.DIRS:
		var enemy := enemy_at(cell + dir)
		if enemy != null:
			return enemy
	return null


## The wick's blow: the enemy it faces, else any enemy beside it.
func _swing() -> void:
	wick.attack_cooldown = WICK_ATTACK_TICKS
	var target := enemy_at(wick.cell + wick.facing)
	if target == null:
		target = enemy_beside(wick.cell)
	if target == null:
		return
	target.hp -= wick.damage
	target.hit_at = tick
	target.alert = maxi(target.alert, MEMORY_TICKS)
	if target.hp <= 0:
		_snuff(target)
	else:
		enemy_hit.emit(target)


func _snuff(enemy: Actor) -> void:
	enemies.erase(enemy)
	_occupied.erase(enemy.cell)
	embers += enemy.embers
	enemy_snuffed.emit(enemy)
	if enemies.is_empty():
		stairs_open = true
		stairs_opened.emit()


## Takes hp from the wick, unless a hurt a moment ago still gives it mercy.
func hurt_wick(amount: int) -> void:
	if wick.mercy > 0 or wick.hp <= 0:
		return
	wick.hp = maxi(wick.hp - amount, 0)
	wick.mercy = MERCY_TICKS
	wick_hurt.emit(amount)


## Plays the floor with a bot in the wick's place: "cleared", "dead", or "stuck" after max_ticks.
func play_out(bot: Bot, max_ticks: int) -> String:
	for i in max_ticks:
		var choice := bot.choose(self)
		step(choice.move, choice.attack)
		if done:
			return "cleared"
		if wick.hp <= 0:
			return "dead"
	return "stuck"
