extends GutTest
## Hidden acceptance for the prototype-to-alpha milestone: two floors with shades and cinder bats, Meta's bank and
## vigor, and a SaveStore that keeps the meta progress and the run in progress.

const PATH := "user://test_hidden_alpha.json"

var floors := Floors.from_files()


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_two_floors_with_bats():
	assert_true(floors.has_floor(1))
	assert_true(floors.has_floor(2))
	assert_has(floors.spec(2).enemies, "bat")
	var bat := floors.kind("bat")
	assert_eq(int(bat.get("hp", 0)), 1)
	assert_lt(int(bat.get("move_ticks", 99)), int(floors.kind("shade").move_ticks))
	for seed_value in range(1, 31):
		var dungeon := Dungeon.generate(seed_value * 1009 + 2, floors.spec(2))
		assert_eq(dungeon.unreachable_cells(), 0)


func test_hidden_meta_banks_and_buys():
	var save := SaveStore.defaults()
	Meta.bank(save, 10, 2, true)
	Meta.bank(save, 7, 1, false)
	assert_eq(int(save.meta.embers), 13)
	assert_eq(int(save.meta.best_floor), 2)
	assert_eq(int(save.meta.runs), 2)
	assert_true(Meta.buy_vigor(save))
	assert_eq(int(save.meta.embers), 8)
	assert_false(Meta.buy_vigor(save), "the second level costs 10")
	Meta.bank(save, 8, 1, true)
	assert_true(Meta.buy_vigor(save))
	assert_eq(int(save.meta.embers), 6)
	assert_eq(int(save.meta.vigor), 2)
	assert_eq(Meta.max_hp(save), 7)


func test_hidden_the_save_keeps_meta_and_the_run():
	var store := SaveStore.new(PATH)
	var save := SaveStore.defaults()
	Meta.bank(save, 12, 2, true)
	assert_true(Meta.buy_vigor(save))
	var run := Run.new(31, Meta.max_hp(save))
	run.floor_number = 2
	run.hp = 4
	run.embers = 3
	save.run = run.to_dict()
	assert_true(store.write(save))
	var back := store.read()
	assert_eq(int(back.meta.embers), 7)
	assert_eq(int(back.meta.vigor), 1)
	var resumed := Run.from_dict(back.run)
	assert_eq(resumed.floor_number, 2)
	assert_eq(resumed.hp, 4)
	assert_eq(resumed.max_hp, 6)
	assert_eq(resumed.floor_seed(), run.floor_seed())


func test_hidden_continue_carries_on_the_run():
	var game: Node2D = load("res://game/game.tscn").instantiate()
	var run := Run.new(31, 6)
	run.floor_number = 2
	run.hp = 4
	game.setup(floors, LaunchOptions.parse(PackedStringArray()), 6, run.to_dict())
	add_child_autofree(game)
	await wait_physics_frames(2)
	assert_eq(game.floor_number, 2)
	assert_eq(game.hp, 4)
	assert_eq(game.world.dungeon.to_text(), Dungeon.generate(run.floor_seed(), floors.spec(2)).to_text())
