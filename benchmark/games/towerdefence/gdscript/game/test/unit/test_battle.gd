extends GutTest
## Battle: building, waves and their schedule, the end of a map, and the seed.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func _wave(enemy: String, count: int, gap := 30, bonus := 10) -> Dictionary:
	return {"number": 1, "bonus": bonus, "groups": [{"enemy": enemy, "count": count, "gap": gap, "delay": 0}]}


func _field(gold := 200, waves: Array = []) -> Battle:
	return Battle.custom(catalog, ["S.......", "........", ".......G"], gold, 10, waves)


func _run_wave(battle: Battle, limit := 6000) -> void:
	var start := battle.wave
	battle.start_wave()
	while battle.wave == start + 1 and battle.phase == Battle.Phase.WAVE and battle.ticks < limit:
		battle.step()


func test_placing_a_tower_spends_its_cost():
	var battle := _field(200)
	assert_true(battle.place("thorn", Vector2i(3, 1)))
	assert_eq(battle.gold, 200 - catalog.cost("thorn"))
	assert_eq(battle.towers[Vector2i(3, 1)].level, 1)


func test_a_tower_cannot_go_on_rocks_the_gate_the_store_or_another_tower():
	var battle := Battle.custom(catalog, ["S.#.", "....", "...G"], 500, 10, [])
	assert_false(battle.place("thorn", Vector2i(2, 0)), "a rock")
	assert_false(battle.place("thorn", Vector2i(0, 0)), "the gate")
	assert_false(battle.place("thorn", Vector2i(3, 2)), "the store")
	assert_true(battle.place("thorn", Vector2i(1, 1)))
	assert_false(battle.place("puff", Vector2i(1, 1)), "a tower already")
	assert_false(battle.place("bramble", Vector2i(3, 0)), "no such tower")


func test_a_tower_on_the_route_sends_it_round():
	var battle := _field()
	var cell := battle.map.route[3]
	assert_true(battle.place("thorn", cell))
	assert_false(battle.map.route.has(cell))
	assert_eq(battle.map.route[0], battle.map.gate)
	assert_eq(battle.map.route[-1], battle.map.store)


func test_no_tower_on_a_cell_a_pest_is_heading_to():
	var battle := _field(500, [_wave("beetle", 1)])
	battle.start_wave()
	for i in 80:
		battle.step()
	var pest: Enemy = battle.enemies[0]
	assert_false(battle.place("thorn", pest.target()))
	assert_false(battle.place("thorn", pest.cell()))


func test_a_wave_sends_its_pests_on_schedule_from_the_gate():
	var battle := _field(100, [_wave("aphid", 3, 20)])
	assert_true(battle.start_wave())
	battle.step()
	assert_eq(battle.enemies.size(), 1)
	assert_eq(battle.enemies[0].cell(), battle.map.gate)
	for i in 20:
		battle.step()
	assert_eq(battle.enemies.size(), 2)
	for i in 20:
		battle.step()
	assert_eq(battle.enemies.size(), 3)
	assert_eq(battle.pending(), 0)


func test_a_wave_cannot_start_while_one_is_under_way():
	var battle := _field(100, [_wave("aphid", 3), _wave("aphid", 3)])
	assert_true(battle.start_wave())
	assert_false(battle.start_wave())
	assert_eq(battle.wave, 1)


func test_the_next_wave_starts_by_itself_after_the_break():
	var battle := _field(100, [_wave("aphid", 1), _wave("aphid", 1)])
	_run_wave(battle)
	assert_eq(battle.phase, Battle.Phase.BUILD)
	assert_eq(battle.break_left, Battle.BREAK_TICKS)
	for i in Battle.BREAK_TICKS:
		battle.step()
	assert_eq(battle.wave, 2)
	assert_eq(battle.phase, Battle.Phase.WAVE)


func test_clearing_the_last_wave_wins_the_map():
	var battle := _field(100, [_wave("aphid", 2)])
	var over := []
	battle.battle_over.connect(func(won: bool) -> void: over.append(won))
	_run_wave(battle)
	assert_eq(battle.phase, Battle.Phase.WON)
	assert_eq(over, [true])
	assert_false(battle.place("thorn", Vector2i(3, 1)), "nothing is built once it is over")


func test_the_same_seed_plays_the_same_battle():
	var a := Battle.create(catalog, "meadow", 7)
	var b := Battle.create(catalog, "meadow", 7)
	for battle in [a, b]:
		battle.place("thorn", Vector2i(3, 3))
		battle.start_wave()
		for i in 400:
			battle.step()
	assert_eq(a.enemies.size(), b.enemies.size())
	for i in a.enemies.size():
		assert_eq(a.enemies[i].pos, b.enemies[i].pos)
	assert_eq(a.gold, b.gold)


func test_seeds_vary_the_pests_speeds():
	var a := Battle.create(catalog, "meadow", 1)
	var b := Battle.create(catalog, "meadow", 2)
	for battle in [a, b]:
		battle.start_wave()
		battle.step()
	assert_ne(a.enemies[0].speed, b.enemies[0].speed)
