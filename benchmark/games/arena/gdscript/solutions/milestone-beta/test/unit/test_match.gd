extends GutTest
## ArenaMatch: warm-up, rounds, points, the end of a match and slots changing hands.

var arena: ArenaMatch


func before_each():
	arena = ArenaMatch.new(Court.load_all())
	for i in ArenaMatch.WARMUP_TICKS:
		arena.advance()


func _out(slot: int, by: int) -> void:
	for i in ArenaMatch.HP:
		arena._damage(by, slot)


func test_the_first_round_starts_after_the_warmup():
	assert_eq(arena.state, ArenaMatch.State.ROUND)
	assert_eq(arena.round_number, 1)
	assert_eq(arena.alive_slots(), [0, 1, 2, 3])
	assert_eq(arena.court.id, "cinder_pit")


func test_five_hits_put_a_glimmer_out():
	for i in ArenaMatch.HP - 1:
		arena._damage(0, 1)
	assert_true(arena.fighters[1].alive)
	assert_eq(arena.fighters[1].hp, 1)
	arena._damage(0, 1)
	assert_false(arena.fighters[1].alive)


func test_the_last_one_standing_wins_the_round():
	_out(1, 0)
	_out(2, 0)
	assert_eq(arena.state, ArenaMatch.State.ROUND)
	_out(3, 0)
	assert_eq(arena.state, ArenaMatch.State.INTERMISSION)
	assert_eq(arena.scores, [1, 0, 0, 0])


func test_rounds_alternate_the_courts_and_the_spawns():
	_out(1, 0)
	_out(2, 0)
	_out(3, 0)
	for i in ArenaMatch.INTERMISSION_TICKS:
		arena.advance()
	assert_eq(arena.round_number, 2)
	assert_eq(arena.court.id, "hollow_ring")
	assert_eq(arena.fighters[0].position(), Vector2(arena.court.spawns[1]))
	assert_eq(arena.alive_slots().size(), 4)
	assert_eq(arena.fighters[1].hp, ArenaMatch.HP)


func test_match_point_and_the_end_of_the_match():
	arena.scores[2] = ArenaMatch.TARGET - 1
	assert_true(arena.is_match_point())
	_out(0, 2)
	_out(1, 2)
	_out(3, 2)
	assert_eq(arena.state, ArenaMatch.State.OVER)
	assert_eq(arena.winner, 2)
	assert_eq(arena.matches, 1)


func test_a_new_owner_starts_from_nothing():
	arena.scores[1] = 2
	arena.set_owner(1, 77)
	assert_eq(arena.owners[1], 77)
	assert_eq(arena.scores[1], 0)
	assert_false(arena.fighters[1].alive, "back next round")


func test_a_restart_keeps_the_owners_and_clears_the_scores():
	arena.set_owner(1, 77)
	arena.scores[0] = 2
	arena.restart()
	assert_eq(arena.state, ArenaMatch.State.WARMUP)
	assert_eq(arena.scores, [0, 0, 0, 0])
	assert_eq(arena.owners[1], 77)


func test_a_snapshot_loads_into_another_match():
	arena._damage(0, 2)
	var copy := ArenaMatch.new(Court.load_all())
	copy.load_snapshot(arena.snapshot())
	assert_eq(copy.round_number, 1)
	assert_eq(copy.fighters[2].hp, ArenaMatch.HP - 1)
	assert_eq(copy.fighters[3].position(), arena.fighters[3].position())
	assert_eq(copy.state, ArenaMatch.State.ROUND)
