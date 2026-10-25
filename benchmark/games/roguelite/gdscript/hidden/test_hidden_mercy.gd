extends GutTest
## Hidden check for the prototype's add-feature: mercy. A hurt that lands gives the wick World.MERCY_TICKS (30) ticks of
## mercy, counted down by World.step; hurts during mercy take nothing, from hurt_wick or from enemies' blows.

var floors := Floors.from_files()


func _world(rows: Array) -> World:
	return World.create(Dungeon.from_text(PackedStringArray(rows)), floors.kinds, 1, 5, 5)


func test_hidden_mercy_lasts_thirty_ticks():
	assert_eq(World.MERCY_TICKS, 30)
	var world := _world(["#####", "#S.>#", "#####"])
	assert_eq(world.wick.mercy, 0)
	world.hurt_wick(1)
	assert_eq(world.wick.hp, 4)
	assert_eq(world.wick.mercy, 30)
	for i in 29:
		world.step(Vector2i.ZERO, false)
	world.hurt_wick(1)
	assert_eq(world.wick.hp, 4, "tick 29: still mercy")
	world.step(Vector2i.ZERO, false)
	assert_eq(world.wick.mercy, 0)
	world.hurt_wick(2)
	assert_eq(world.wick.hp, 2, "mercy is over")


func test_hidden_a_hurt_that_misses_gives_no_new_mercy():
	var world := _world(["#####", "#S.>#", "#####"])
	world.hurt_wick(1)
	for i in 10:
		world.step(Vector2i.ZERO, false)
	world.hurt_wick(1)
	assert_eq(world.wick.mercy, 20, "the second hurt did not start mercy again")


func test_hidden_blows_respect_mercy():
	var world := _world(["#######", "#.sSs.#", "#..s..#", "#######"])
	for i in World.WINDUP_TICKS + 5:
		world.step(Vector2i.ZERO, false)
	assert_eq(world.wick.hp, 4, "three shades strike together, one blow lands")
	for i in 45:
		world.step(Vector2i.ZERO, false)
	assert_lt(world.wick.hp, 4, "after mercy, blows land again")
