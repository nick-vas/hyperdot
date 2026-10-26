extends GutTest
## Sim: the movement and shots the server and the clients share.

var court: Court


func before_each():
	court = Court.load_all()[0]


func _fighter(x: int, y: int, slot := 0) -> Fighter:
	var f := Fighter.new()
	f.slot = slot
	f.x = x
	f.y = y
	f.alive = true
	return f


func _make_input(mx: int, my: int, fire := false, dash := false) -> Dictionary:
	var input := Sim.idle()
	input.mx = mx
	input.my = my
	input.fire = fire
	input.dash = dash
	return input


func test_a_straight_step_moves_eight_pixels():
	var f := _fighter(100, 200)
	Sim.step(f, _make_input(1, 0), court)
	assert_eq(Vector2i(f.x, f.y), Vector2i(108, 200))


func test_a_diagonal_step_moves_six_on_each_axis():
	var f := _fighter(100, 200)
	Sim.step(f, _make_input(1, 1), court)
	assert_eq(Vector2i(f.x, f.y), Vector2i(106, 206))


func test_a_pillar_stops_a_fighter_flush_against_it():
	# The Cinder Pit's core pillar starts at x 540: a 16-pixel half side stops the centre at 524.
	var f := _fighter(520, 300)
	Sim.step(f, _make_input(1, 0), court)
	assert_eq(f.x, 524)
	Sim.step(f, _make_input(1, 0), court)
	assert_eq(f.x, 524, "no further")


func test_the_court_edge_holds_a_fighter_in():
	var f := _fighter(20, 400)
	Sim.step(f, _make_input(-1, 0), court)
	assert_eq(f.x, Court.HALF)


func test_a_dash_triples_the_speed_for_five_ticks_then_rests():
	var f := _fighter(100, 400)
	Sim.step(f, _make_input(0, 0, false, true), court)
	assert_eq(f.dash_ticks, Sim.DASH_TICKS - 1)
	f = _fighter(100, 400)
	for i in Sim.DASH_TICKS:
		Sim.step(f, _make_input(1, 0, false, i == 0), court)
	assert_eq(f.x, 100 + Sim.DASH_TICKS * Sim.SPEED * Sim.DASH_FACTOR)
	Sim.step(f, _make_input(1, 0, false, true), court)
	assert_eq(f.x, 100 + Sim.DASH_TICKS * Sim.SPEED * Sim.DASH_FACTOR + Sim.SPEED, "resting: a plain step")


func test_firing_starts_the_cooldown():
	var f := _fighter(100, 400)
	assert_true(Sim.step(f, _make_input(0, 0, true), court))
	assert_eq(f.cooldown, Sim.FIRE_COOLDOWN)
	assert_false(Sim.step(f, _make_input(0, 0, true), court), "cooling down")


func test_a_dead_fighter_does_not_move():
	var f := _fighter(100, 400)
	f.alive = false
	assert_false(Sim.step(f, _make_input(1, 0, true), court))
	assert_eq(f.x, 100)


func test_a_shot_hits_the_nearest_fighter_in_line():
	var fighters := [_fighter(100, 100, 0), _fighter(400, 100, 1), _fighter(300, 100, 2), _fighter(900, 600, 3)]
	var shot := Sim.trace(court, fighters, 0)
	assert_eq(shot.target, 2)
	assert_almost_eq(float(shot.x), 300.0 - Sim.RADIUS, 1.0)


func test_a_pillar_stops_a_shot():
	# The top pillar (x 570 to 630) stands between them.
	var fighters := [_fighter(400, 100, 0), _fighter(800, 100, 1), _fighter(100, 600, 2), _fighter(1100, 600, 3)]
	var shot := Sim.trace(court, fighters, 0)
	assert_eq(shot.target, -1)
	assert_almost_eq(float(shot.x), 570.0, 1.0)


func test_input_from_the_wire_is_clamped():
	var input := Sim.sanitize({"seq": 4, "mx": 5, "my": -9, "ax": 99999, "fire": 1})
	assert_eq(input.mx, 1)
	assert_eq(input.my, -1)
	assert_eq(input.ax, 10000)
	assert_true(input.fire)
	assert_eq(input.claim, -1)
