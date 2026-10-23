extends GutTest
## The bot and the balance it measures: seed 1's run reaches the bottom, and every floor is fair to a wick at full hp,
## neither a wall nor a walk.

var floors := Floors.from_files()


## Plays a whole run as the game does: the stairs relight one hp. Returns the floor reached and whether it was cleared.
func _run(seed_value: int) -> Dictionary:
	var run := Run.new(seed_value, Meta.BASE_HP)
	for number in range(1, floors.count() + 1):
		run.floor_number = number
		var world := World.create(Dungeon.generate(run.floor_seed(), floors.spec(number)), floors.kinds, run.floor_seed(), run.hp, run.max_hp)
		var result := world.play_out(Bot.new(), 7200)
		if result != "cleared":
			return {"floor": number, "won": false, "result": result}
		run.hp = mini(world.wick.hp + 1, run.max_hp)
	return {"floor": floors.count(), "won": true, "result": "cleared"}


func test_the_bot_reaches_the_bottom_with_seed_1():
	var outcome := _run(1)
	assert_true(outcome.won, "stopped on floor %d: %s" % [outcome.floor, outcome.result])


func test_every_floor_is_fair_to_a_wick_at_full_hp():
	for number in range(1, floors.count() + 1):
		var cleared := 0
		var lost := 0
		for seed_value in range(1, 21):
			var seed_of_floor := seed_value * 1009 + number
			var world := World.create(Dungeon.generate(seed_of_floor, floors.spec(number)), floors.kinds, seed_of_floor, Meta.BASE_HP, Meta.BASE_HP)
			var result := world.play_out(Bot.new(), 7200)
			assert_ne(result, "stuck", "floor %d seed %d: the bot found nothing to do" % [number, seed_value])
			if result == "cleared":
				cleared += 1
			lost += Meta.BASE_HP - world.wick.hp
		assert_gte(cleared, 15, "floor %d cleared in %d of 20" % [number, cleared])
		assert_gte(lost, 6, "floor %d cost %d hp over 20 seeds: too easy" % [number, lost])
