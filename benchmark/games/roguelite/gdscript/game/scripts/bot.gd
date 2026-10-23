class_name Bot
extends RefCounted
## Plays the wick for --autoplay, the balance tests and the bot runs: strike whatever stands beside it, else walk the
## shortest way to the nearest enemy it can reach, and once the stairs are open, walk to them. It reads only what a
## player sees on screen and sends only what a player can press.


## { "move": a step of Dungeon.DIRS or zero, "attack": bool } for this tick.
func choose(world: World) -> Dictionary:
	var wick := world.wick
	if world.enemy_beside(wick.cell) != null:
		return {"move": Vector2i.ZERO, "attack": true}
	if wick.move_cooldown > 0:
		return {"move": Vector2i.ZERO, "attack": false}
	var target := _target(world)
	if target == wick.cell:
		return {"move": Vector2i.ZERO, "attack": false}
	var field := world.dungeon.distance_field(target)
	var best := Vector2i.ZERO
	var best_distance := field[world.dungeon.index(wick.cell)]
	for dir in Dungeon.DIRS:
		var next := wick.cell + dir
		if not world.dungeon.is_floor(next) or world.enemy_at(next) != null:
			continue
		var distance := field[world.dungeon.index(next)]
		if distance >= 0 and distance < best_distance:
			best_distance = distance
			best = dir
	return {"move": best, "attack": false}


## The nearest enemy the wick can walk to, else the open stairs, else where it stands (nothing to do).
func _target(world: World) -> Vector2i:
	var field := world.dungeon.distance_field(world.wick.cell)
	var best := world.wick.cell
	var best_distance := 1 << 30
	for enemy in world.enemies:
		if not world.dungeon.in_bounds(enemy.cell):
			continue
		var distance := field[world.dungeon.index(enemy.cell)]
		if distance >= 0 and distance < best_distance:
			best_distance = distance
			best = enemy.cell
	if world.enemies.is_empty() and world.stairs_open:
		return world.dungeon.stairs
	return best
