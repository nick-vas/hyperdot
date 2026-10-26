extends GutTest
## Hidden check for the Hollow Ring (the alpha's add-content, and the beta milestone): the second court, played in the
## second round, with four spawns that are clear, spread out and out of each other's sight, and matches on it that end.

func _ring() -> Court:
	for court in Court.load_all():
		if court.id == "hollow_ring":
			return court
	return null


func test_hidden_the_ring_is_the_second_court():
	var courts := Court.load_all()
	assert_eq(courts.size(), 2)
	assert_eq(courts[1].id, "hollow_ring")
	assert_eq(courts[1].name_key, "COURT_HOLLOW_RING")
	assert_ne(TranslationServer.translate("COURT_HOLLOW_RING"), "COURT_HOLLOW_RING", "its name is translated")


func test_hidden_the_ring_has_four_fair_spawns():
	var ring := _ring()
	assert_not_null(ring)
	if ring == null:
		return
	assert_eq(ring.spawns.size(), 4)
	assert_gte(ring.walls.size(), 3, "pillars to fight around")
	for spawn in ring.spawns:
		assert_true(ring.box_free(spawn.x, spawn.y), "spawn %s is clear" % spawn)
		for other in ring.spawns:
			if other == spawn:
				continue
			assert_false(ring.clear_line(Vector2(spawn), Vector2(other)), "%s cannot see %s" % [spawn, other])
			assert_gte(Vector2(spawn).distance_to(Vector2(other)), 300.0, "%s is far from %s" % [spawn, other])


func test_hidden_round_two_is_on_the_ring():
	var arena := ArenaMatch.new(Court.load_all())
	for i in ArenaMatch.WARMUP_TICKS:
		arena.advance()
	for slot in [1, 2, 3]:
		for i in ArenaMatch.HP:
			arena._damage(0, slot)
	for i in ArenaMatch.INTERMISSION_TICKS:
		arena.advance()
	assert_eq(arena.round_number, 2)
	assert_eq(arena.court.id, "hollow_ring")
	for f in arena.fighters:
		assert_true(arena.court.box_free(f.x, f.y))


func test_hidden_bot_rounds_on_the_ring_end():
	var ring := _ring()
	if ring == null:
		fail_test("no Hollow Ring")
		return
	var only_ring: Array[Court] = [ring]
	for match_seed in [1, 2, 3, 4]:
		var server := ArenaServer.new(only_ring, match_seed)
		for i in 150 * Sim.TICK_RATE:
			server.tick()
			if server.arena.state == ArenaMatch.State.OVER:
				break
		assert_eq(server.arena.state, ArenaMatch.State.OVER, "seed %d: a bot match on the ring ends within 150 s" % match_seed)
