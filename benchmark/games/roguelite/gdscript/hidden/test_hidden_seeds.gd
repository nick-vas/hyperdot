extends GutTest
## Hidden check for the beta's fix-bug: a seed always builds the same floor, whatever the global generator did before;
## seeds that differ build different floors; and generating leaves the global generator alone.

var floors := Floors.from_files()


func test_hidden_the_same_seed_builds_the_same_floor_in_any_order():
	for number in range(1, floors.count() + 1):
		var first := Dungeon.generate(4242 + number, floors.spec(number)).to_text()
		randomize()
		Dungeon.generate(5, floors.spec(1))
		randomize()
		assert_eq(Dungeon.generate(4242 + number, floors.spec(number)).to_text(), first, "floor %d" % number)


func test_hidden_a_floor_plays_the_same_from_one_seed():
	var texts: Array[String] = []
	for attempt in 2:
		randomize()
		var world := World.create(Dungeon.generate(77 * 1009 + 2, floors.spec(2)), floors.kinds, 77 * 1009 + 2, 5, 5)
		var bot := Bot.new()
		for i in 600:
			var choice := bot.choose(world)
			world.step(choice.move, choice.attack)
		texts.append("%s %d %d" % [world.wick.cell, world.wick.hp, world.enemies.size()])
	assert_eq(texts[1], texts[0])


func test_hidden_seeds_that_differ_build_differently():
	var seen := {}
	for seed_value in range(300, 330):
		seen[Dungeon.generate(seed_value, floors.spec(2)).to_text()] = true
	assert_eq(seen.size(), 30)


func test_hidden_generating_leaves_the_global_generator_alone():
	seed(99)
	var expected := randi()
	seed(99)
	Dungeon.generate(7, floors.spec(1))
	World.create(Dungeon.generate(8, floors.spec(2)), floors.kinds, 8, 5, 5)
	assert_eq(randi(), expected)
