extends GutTest
## The sap: what pests pay when they fall, what a wave pays when it is cleared, and what upgrades cost.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func _wave(enemy: String, count: int, bonus: int) -> Dictionary:
	return {"number": 1, "bonus": bonus, "groups": [{"enemy": enemy, "count": count, "gap": 30, "delay": 0}]}


func test_clearing_a_wave_pays_its_bonus():
	var battle := Battle.custom(catalog, ["S...G"], 100, 5, [_wave("aphid", 1, 15)])
	battle.start_wave()
	while battle.phase == Battle.Phase.WAVE and battle.ticks < 2000:
		battle.step()
	assert_eq(battle.lives, 4, "the aphid got to the store")
	assert_eq(battle.gold, 115)


func test_a_fallen_pest_pays_its_reward():
	var battle := Battle.custom(catalog, ["S...G"], 100, 5, [_wave("aphid", 1, 0)])
	var paid := []
	battle.enemy_killed.connect(func(enemy: Enemy) -> void: paid.append(enemy.reward))
	battle.start_wave()
	battle.step()
	battle.enemies[0].hp = 1
	battle._wound(battle.enemies[0], 3, 0.0)
	assert_eq(paid, [int(catalog.enemies["aphid"].reward)])
	assert_eq(battle.gold, 100 + int(catalog.enemies["aphid"].reward))


func test_an_upgrade_costs_its_price_and_raises_the_tower():
	var battle := Battle.custom(catalog, ["S...G", "....."], 300, 5, [])
	battle.place("thorn", Vector2i(1, 1))
	var price := catalog.upgrade_cost("thorn", 2)
	assert_true(battle.upgrade(Vector2i(1, 1)))
	assert_eq(battle.gold, 300 - catalog.cost("thorn") - price)
	assert_eq(battle.towers[Vector2i(1, 1)].level, 2)
	assert_gt(int(catalog.stats("thorn", 2).damage), int(catalog.stats("thorn", 1).damage))


func test_no_upgrade_past_the_last_level_or_without_the_sap():
	var battle := Battle.custom(catalog, ["S...G", "....."], 1000, 5, [])
	battle.place("puff", Vector2i(1, 1))
	assert_true(battle.upgrade(Vector2i(1, 1)))
	assert_true(battle.upgrade(Vector2i(1, 1)))
	assert_false(battle.upgrade(Vector2i(1, 1)), "level 3 is the last")
	var poor := Battle.custom(catalog, ["S...G", "....."], catalog.cost("acorn"), 5, [])
	poor.place("acorn", Vector2i(1, 1))
	assert_false(poor.upgrade(Vector2i(1, 1)))
	assert_eq(poor.gold, 0)
