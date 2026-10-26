extends GutTest
## Hidden check for the alpha's fix-bug: a placement turns every pest on the field at once onto the shortest way left
## from the cell it is heading to; none walks up to the tower, and nothing searches paths without a placement.

const FIELD := ["S.......", "........", ".......G"]

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func _tough(battle: Battle, cell: Vector2i) -> Enemy:
	var pest := battle.spawn_at("beetle", cell)
	pest.hp = 1000000
	return pest


func test_hidden_the_pests_turn_at_once():
	var battle := Battle.custom(catalog, FIELD, 500, 10, [])
	var pest := _tough(battle, Vector2i(1, 0))
	var ahead: Vector2i = pest.path[3]
	assert_true(battle.place("thorn", ahead))
	assert_false(pest.path.has(ahead), "its way already goes round the tower")
	assert_eq(pest.path.size(), battle.map.path_from(pest.target()).size(), "the shortest way left")
	assert_eq(pest.path[-1], battle.map.store)


func test_hidden_a_pest_goes_round_and_reaches_the_store():
	var battle := Battle.custom(catalog, FIELD, 500, 10, [])
	var pest := _tough(battle, Vector2i(1, 0))
	var ahead: Vector2i = pest.path[2]
	var steps := battle.map.path_from(pest.target()).size()
	battle.place("thorn", ahead)
	var expected := (pest.pos.distance_to(Enemy.centre(pest.target())) + float(battle.map.path_from(pest.target()).size() - 1)) / pest.speed
	var stood := 0
	var last := pest.pos
	var ticks := 0
	while pest.alive and ticks < 3000:
		battle.step()
		ticks += 1
		if pest.alive:
			stood += 1 if pest.pos == last else 0
			last = pest.pos
	assert_false(pest.alive)
	assert_eq(battle.leaks, 1, "it reached the store")
	assert_eq(stood, 0, "it never stood still")
	assert_lt(float(ticks), expected * 1.6 + 5.0, "it took the way round at once (%d steps before)" % steps)


func test_hidden_every_pest_on_the_field_turns():
	var battle := Battle.custom(catalog, FIELD, 500, 10, [])
	var pests: Array[Enemy] = []
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 2)]:
		pests.append(_tough(battle, cell))
	assert_true(battle.place("thorn", Vector2i(4, 1)))
	assert_true(battle.place("thorn", Vector2i(5, 2)))
	for pest in pests:
		assert_false(pest.path.has(Vector2i(4, 1)))
		assert_false(pest.path.has(Vector2i(5, 2)))
		assert_eq(pest.path.size(), battle.map.path_from(pest.target()).size())


func test_hidden_paths_are_searched_on_placements_only():
	var battle := Battle.custom(catalog, FIELD, 5000, 10, [])
	for x in 6:
		_tough(battle, Vector2i(x, 1))
	for i in 10:
		battle.step()
	var before := battle.map.path_queries
	for i in 120:
		battle.step()
	assert_eq(battle.map.path_queries, before, "no placement, no search")
	before = battle.map.path_queries
	assert_true(battle.place("thorn", Vector2i(6, 0)))
	assert_lte(battle.map.path_queries - before, 2 * battle.enemies.size() + 4, "one placement, a search or two per pest")
