extends GutTest
## The rules a match is played by: damage and knock-outs, the cooldown, pillars against shots and glimmers, rounds and
## the end of the match.

var arena: ArenaMatch


func before_each():
	arena = ArenaMatch.new(Court.load_all())
	for i in ArenaMatch.WARMUP_TICKS:
		arena.advance()


func _place(slot: int, x: int, y: int) -> void:
	arena.fighters[slot].x = x
	arena.fighters[slot].y = y


func _fire(slot: int, ax: int, ay: int) -> void:
	var input := Sim.idle()
	input.ax = ax
	input.ay = ay
	input.fire = true
	arena.apply(slot, input)


func _out(slot: int, by: int) -> void:
	for i in ArenaMatch.HP:
		arena._damage(by, slot)


func test_a_shot_in_the_open_takes_one_health():
	_place(0, 100, 220)
	_place(1, 400, 220)
	_fire(0, 1, 0)
	assert_eq(arena.fighters[1].hp, ArenaMatch.HP - 1)


func test_a_pillar_takes_the_shot():
	# The Cinder Pit's top pillar spans x 570 to 630 down to y 170.
	_place(0, 400, 100)
	_place(1, 800, 100)
	_fire(0, 1, 0)
	assert_eq(arena.fighters[1].hp, ArenaMatch.HP)


func test_the_cooldown_holds_the_next_shot():
	_place(0, 100, 220)
	_place(1, 400, 220)
	_fire(0, 1, 0)
	_fire(0, 1, 0)
	assert_eq(arena.fighters[1].hp, ArenaMatch.HP - 1)
	for i in Sim.FIRE_COOLDOWN - 2:
		arena.apply(0, Sim.idle())
	_fire(0, 1, 0)
	assert_eq(arena.fighters[1].hp, ArenaMatch.HP - 2, "ready again after the cooldown")


func test_the_last_hit_knocks_a_glimmer_out():
	_out(1, 0)
	assert_false(arena.fighters[1].alive)
	assert_eq(arena.alive_slots(), [0, 2, 3])


func test_the_last_one_standing_scores_the_round():
	_out(1, 0)
	_out(2, 0)
	_out(3, 0)
	assert_eq(arena.state, ArenaMatch.State.INTERMISSION)
	assert_eq(arena.scores, [1, 0, 0, 0])


func test_the_target_ends_the_match():
	arena.scores[3] = ArenaMatch.TARGET - 1
	_out(0, 3)
	_out(1, 3)
	_out(2, 3)
	assert_eq(arena.state, ArenaMatch.State.OVER)
	assert_eq(arena.winner, 3)


func test_a_pillar_stops_a_glimmer():
	_place(0, 500, 320)
	for i in 10:
		arena.apply(0, {"seq": i, "mx": 1, "my": 0, "ax": 0, "ay": 0, "fire": false, "dash": false, "claim": -1})
	assert_eq(arena.fighters[0].x, 540 - Court.HALF)
