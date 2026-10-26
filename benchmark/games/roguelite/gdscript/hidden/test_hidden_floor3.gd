extends GutTest
## Hidden check for the alpha's add-content: floor 3, The Drowned Nave, with the tallow brute, generated whole, and fair
## to the bot at 5 hp.

var floors := Floors.from_files()


func test_hidden_floor_3_is_in_the_data():
	assert_true(floors.has_floor(3))
	var spec := floors.spec(3)
	assert_eq(str(spec.get("name", "")), "FLOOR_3")
	assert_eq(tr("FLOOR_3"), "The Drowned Nave")
	assert_eq(int(spec.get("width", 0)), 44)
	assert_eq(int(spec.get("height", 0)), 26)
	assert_eq(int(spec.rooms[0]), 6)
	assert_eq(int(spec.rooms[1]), 8)
	for kind in ["shade", "bat", "brute"]:
		assert_has(spec.enemies, kind)


func test_hidden_the_brute_is_slow_and_heavy():
	var brute := floors.kind("brute")
	assert_false(brute.is_empty(), "a brute in data/enemies.json")
	assert_eq(str(brute.get("name", "")), "ENEMY_BRUTE")
	assert_eq(tr("ENEMY_BRUTE"), "Tallow brute")
	assert_eq(int(brute.get("hp", 0)), 3)
	assert_eq(int(brute.get("damage", 0)), 2)
	assert_eq(int(brute.get("embers", 0)), 3)
	assert_gt(int(brute.get("move_ticks", 0)), int(floors.kind("shade").move_ticks))


func test_hidden_floor_3_is_whole_and_has_brutes():
	var with_brutes := 0
	for seed_value in range(1, 101):
		var dungeon := Dungeon.generate(seed_value * 1009 + 3, floors.spec(3))
		assert_eq(dungeon.unreachable_cells(), 0, "seed %d" % seed_value)
		for spawn in dungeon.spawns:
			if spawn.kind == "brute":
				with_brutes += 1
				break
	assert_gt(with_brutes, 60, "brutes on %d of 100 floors" % with_brutes)


func test_hidden_floor_3_is_fair():
	var cleared := 0
	var lost := 0
	for seed_value in range(1, 21):
		var seed_of_floor := seed_value * 1009 + 3
		var world := World.create(Dungeon.generate(seed_of_floor, floors.spec(3)), floors.kinds, seed_of_floor, 5, 5)
		if world.play_out(Bot.new(), 7200) == "cleared":
			cleared += 1
		lost += 5 - world.wick.hp
	assert_gte(cleared, 15, "cleared %d of 20" % cleared)
	assert_gte(lost, 10, "it cost %d hp over 20 floors" % lost)
