extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: four floors, the tallow brute, each floor whole and fair to the bot,
## and saves from version 1.

const PATH := "user://test_hidden_four_floors.json"

var floors := Floors.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_four_floors_and_the_brute():
	assert_eq(floors.count(), 4)
	var brute := floors.kind("brute")
	assert_eq(int(brute.get("hp", 0)), 3)
	assert_eq(int(brute.get("damage", 0)), 2)
	assert_gt(int(brute.get("move_ticks", 0)), int(floors.kind("shade").move_ticks))
	for number in [3, 4]:
		assert_has(floors.spec(number).enemies, "brute")


func test_hidden_every_floor_is_whole_and_fair():
	for number in range(1, 5):
		var cleared := 0
		var lost := 0
		for seed_value in range(1, 21):
			var seed_of_floor := seed_value * 1009 + number
			var dungeon := Dungeon.generate(seed_of_floor, floors.spec(number))
			assert_eq(dungeon.unreachable_cells(), 0)
			var world := World.create(dungeon, floors.kinds, seed_of_floor, 5, 5)
			if world.play_out(Bot.new(), 7200) == "cleared":
				cleared += 1
			lost += 5 - world.wick.hp
		assert_gte(cleared, 15, "floor %d cleared %d of 20" % [number, cleared])
		assert_gt(lost, 0, "floor %d" % number)


func test_hidden_a_version_1_save_loads():
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string('{"version": 1, "embers": 17, "best": 2}')
	file.close()
	var data := SaveStore.new(PATH).read()
	assert_eq(int(data.meta.embers), 17)
	assert_eq(int(data.meta.best_floor), 2)
