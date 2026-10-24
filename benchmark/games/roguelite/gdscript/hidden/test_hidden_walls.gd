extends GutTest
## Hidden check for the beta's fix-playthrough: enemies never stand in the rock, wandering or hunting, on every floor and
## many seeds; none vanishes without a blow; and the stairs stay sealed while one is left.

var floors := Floors.from_files()


func test_hidden_no_enemy_ever_stands_in_rock():
	for number in range(1, floors.count() + 1):
		for seed_value in range(1, 9):
			var seed_of_floor := seed_value * 1009 + number
			var world := World.create(Dungeon.generate(seed_of_floor, floors.spec(number)), floors.kinds, seed_of_floor, 99, 99)
			var count := world.enemies.size()
			var in_rock := 0
			for i in 900:
				world.step(Vector2i.ZERO, false)
				for enemy in world.enemies:
					if not world.dungeon.is_floor(enemy.cell):
						in_rock += 1
			assert_eq(in_rock, 0, "floor %d seed %d: enemies in the rock" % [number, seed_value])
			assert_eq(world.enemies.size(), count, "floor %d seed %d: enemies gone without a blow" % [number, seed_value])
			assert_false(world.stairs_open)


func test_hidden_a_wanderer_walled_in_stays_put():
	var world := World.create(Dungeon.from_text(PackedStringArray([
		"#######",
		"#S#####",
		"#.##s##",
		"#>#####",
		"#######",
	])), floors.kinds, 3, 5, 5)
	for i in 600:
		world.step(Vector2i.ZERO, false)
	assert_eq(world.enemies[0].cell, Vector2i(4, 2))


func test_hidden_the_bot_clears_every_floor_of_seed_1():
	var run := Run.new(1, Meta.BASE_HP)
	for number in range(1, floors.count() + 1):
		run.floor_number = number
		var world := World.create(Dungeon.generate(run.floor_seed(), floors.spec(number)), floors.kinds, run.floor_seed(), 9, 9)
		assert_eq(world.play_out(Bot.new(), 7200), "cleared", "floor %d" % number)
