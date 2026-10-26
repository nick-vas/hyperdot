extends GutTest
## Battle's rules: what towers cost, what pests pay and take, losing the map, and which pest a tower shoots.

const FIELD := ["S.......", "........", ".......G"]

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func _battle(gold := 300, lives := 10) -> Battle:
	return Battle.custom(catalog, FIELD, gold, lives, [])


## A pest that stays where it is put and does not fall to one shot.
func _still(battle: Battle, id: String, cell: Vector2i) -> Enemy:
	var enemy := battle.spawn_at(id, cell)
	enemy.speed = 0.0
	enemy.hp = 1000
	return enemy


func test_a_tower_costs_its_price():
	var battle := _battle(300)
	assert_true(battle.place("acorn", Vector2i(3, 1)))
	assert_eq(battle.gold, 300 - catalog.cost("acorn"))


func test_a_tower_dearer_than_the_sap_left_cannot_be_placed():
	var battle := _battle(catalog.cost("puff") - 1)
	assert_false(battle.can_place("puff", Vector2i(3, 1)))
	assert_false(battle.place("puff", Vector2i(3, 1)))
	assert_eq(battle.towers.size(), 0)
	battle.gold = catalog.cost("puff")
	assert_true(battle.place("puff", Vector2i(3, 1)))
	assert_eq(battle.gold, 0)


func test_a_fallen_pest_pays_its_reward():
	var battle := _battle(200)
	battle.place("thorn", Vector2i(2, 1))
	var pest := battle.spawn_at("beetle", Vector2i(2, 0))
	pest.speed = 0.0
	pest.hp = 1
	var before := battle.gold
	for i in 30:
		battle.step()
	assert_false(pest.alive)
	assert_eq(battle.kills, 1)
	assert_eq(battle.gold, before + int(catalog.enemies["beetle"].reward))


func test_a_pest_at_the_store_takes_its_own_number_of_seeds():
	var battle := _battle(0, 10)
	battle.spawn_at("beetle", Vector2i(6, 2))
	for i in 120:
		battle.step()
	assert_eq(battle.leaks, 1)
	assert_eq(battle.lives, 10 - int(catalog.enemies["beetle"].leak))
	assert_eq(int(catalog.enemies["beetle"].leak), 2)


func test_the_map_is_lost_when_the_last_seed_goes():
	var battle := _battle(0, 2)
	var over := []
	battle.battle_over.connect(func(won: bool) -> void: over.append(won))
	battle.spawn_at("beetle", Vector2i(6, 2))
	for i in 120:
		battle.step()
	assert_eq(battle.lives, 0)
	assert_eq(battle.phase, Battle.Phase.LOST)
	assert_eq(over, [false])


func test_a_tower_shoots_only_within_its_range():
	var battle := _battle()
	battle.place("thorn", Vector2i(0, 2))
	_still(battle, "aphid", Vector2i(3, 2))
	for i in 10:
		battle.step()
	assert_eq(battle.shots.size(), 0, "3 cells away, past a range of 2.5")
	_still(battle, "aphid", Vector2i(2, 2))
	for i in 5:
		battle.step()
	assert_eq(battle.shots.size(), 1, "2 cells away")


func test_a_tower_shoots_the_pest_closest_to_the_store():
	var battle := _battle()
	battle.place("thorn", Vector2i(4, 0))
	var ahead := _still(battle, "aphid", Vector2i(5, 1))
	_still(battle, "aphid", Vector2i(2, 1))
	battle.step()
	assert_eq(battle.shots.size(), 1)
	assert_eq(battle.shots[0].target, ahead)


func test_a_splash_hits_every_pest_near_where_it_lands():
	var battle := _battle()
	battle.place("acorn", Vector2i(3, 0))
	var a := _still(battle, "beetle", Vector2i(5, 2))
	var b := _still(battle, "beetle", Vector2i(5, 2))
	b.pos.x -= 0.5
	for i in 60:
		battle.step()
	assert_lt(a.hp, 1000)
	assert_lt(b.hp, 1000)


func test_a_puff_slows_the_pests_it_hits():
	var battle := _battle()
	battle.place("puff", Vector2i(3, 0))
	var pest := _still(battle, "beetle", Vector2i(3, 1))
	pest.speed = 0.01
	for i in 60:
		battle.step()
	assert_gt(pest.slow_ticks, 0)
	assert_almost_eq(pest.pace(), 0.01 * (1.0 - float(catalog.towers["puff"].slow)), 0.0001)
