extends GutTest
## Mercy: after a hurt the wick cannot be hurt again for World.MERCY_TICKS ticks, so a crowd cannot drain it in one go.

var floors := Floors.from_files()


func test_a_hurt_gives_mercy_for_a_while():
	var world := World.create(Dungeon.from_text(PackedStringArray(["#####", "#S.>#", "#####"])), floors.kinds, 1, 5, 5)
	world.hurt_wick(1)
	world.hurt_wick(1)
	assert_eq(world.wick.hp, 4, "the second hurt came during mercy")
	for i in World.MERCY_TICKS:
		world.step(Vector2i.ZERO, false)
	world.hurt_wick(1)
	assert_eq(world.wick.hp, 3, "mercy is over")


func test_two_enemies_beside_the_wick_hurt_it_once_at_first():
	var world := World.create(Dungeon.from_text(PackedStringArray(["#####", "#sSs#", "#####"])), floors.kinds, 1, 5, 5)
	for i in World.WINDUP_TICKS + 5:
		world.step(Vector2i.ZERO, false)
	assert_eq(world.wick.hp, 4)
