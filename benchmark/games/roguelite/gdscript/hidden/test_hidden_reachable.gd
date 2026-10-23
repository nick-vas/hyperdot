extends GutTest
## Hidden check for the prototype's fix-bug: on every floor shape and hundreds of seeds, every room and every floor cell
## can be reached from the start, found by a search of this test's own, and the rooms the floor rolled are all there.

## Floor 1 from the data, and the shapes of bigger floors the game will have.
var specs: Array[Dictionary] = [
	Floors.from_files().spec(1),
	{"width": 42, "height": 24, "rooms": [6, 7], "room_size": [4, 7], "enemies": ["shade"], "per_room": [1, 2]},
	{"width": 44, "height": 26, "rooms": [7, 8], "room_size": [4, 8], "enemies": ["shade"], "per_room": [1, 3]},
]


func _reached(dungeon: Dungeon) -> Dictionary:
	var seen := {dungeon.start: true}
	var queue: Array[Vector2i] = [dungeon.start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + dir
			if not seen.has(next) and next.x >= 0 and next.y >= 0 and next.x < dungeon.width and next.y < dungeon.height \
					and dungeon.tiles[next.y * dungeon.width + next.x] == Dungeon.FLOOR:
				seen[next] = true
				queue.append(next)
	return seen


func test_hidden_every_room_and_cell_is_reachable():
	var failures := PackedStringArray()
	for s in specs.size():
		for seed_value in range(1, 301):
			var dungeon := Dungeon.generate(seed_value * 7 + s, specs[s])
			var seen := _reached(dungeon)
			var floor_count := 0
			for i in dungeon.tiles.size():
				if dungeon.tiles[i] == Dungeon.FLOOR:
					floor_count += 1
			var lost := 0
			for room in dungeon.rooms:
				for y in range(room.position.y, room.end.y):
					for x in range(room.position.x, room.end.x):
						if not seen.has(Vector2i(x, y)):
							lost += 1
			if seen.size() != floor_count or lost > 0:
				failures.append("shape %d seed %d" % [s, seed_value * 7 + s])
	assert_eq(failures.size(), 0, ", ".join(failures.slice(0, 10)))


func test_hidden_the_rooms_rolled_are_all_there():
	for s in specs.size():
		for seed_value in range(1, 101):
			var dungeon := Dungeon.generate(seed_value, specs[s])
			assert_gte(dungeon.rooms.size(), int(specs[s].rooms[0]), "shape %d seed %d" % [s, seed_value])
			for spawn in dungeon.spawns:
				assert_eq(dungeon.tiles[dungeon.index(spawn.cell)], Dungeon.FLOOR, "an enemy on rock")


func test_hidden_the_stairs_and_every_enemy_can_be_reached():
	for seed_value in range(1, 201):
		var dungeon := Dungeon.generate(seed_value * 1009 + 1, specs[0])
		var seen := _reached(dungeon)
		assert_true(seen.has(dungeon.stairs), "seed %d stairs" % seed_value)
		for spawn in dungeon.spawns:
			assert_true(seen.has(spawn.cell), "seed %d: an enemy at %s" % [seed_value, spawn.cell])
