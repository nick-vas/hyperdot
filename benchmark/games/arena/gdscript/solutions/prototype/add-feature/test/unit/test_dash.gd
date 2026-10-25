extends GutTest
## The dash: three times the speed for a few ticks, then a rest, the same on the server and in a client's prediction.

var court: Court


func before_each():
	court = Court.load_all()[0]


func _fighter() -> Fighter:
	var f := Fighter.new()
	f.x = 100
	f.y = 220
	f.alive = true
	return f


func _dash_input(dash: bool) -> Dictionary:
	var input := Sim.idle()
	input.mx = 1
	input.dash = dash
	return input


func test_a_dash_moves_three_times_as_far_for_five_ticks():
	var f := _fighter()
	for i in Sim.DASH_TICKS:
		Sim.step(f, _dash_input(i == 0), court)
	assert_eq(f.x, 100 + Sim.DASH_TICKS * Sim.SPEED * Sim.DASH_FACTOR)
	Sim.step(f, _dash_input(false), court)
	assert_eq(f.x, 100 + Sim.DASH_TICKS * Sim.SPEED * Sim.DASH_FACTOR + Sim.SPEED)


func test_a_dash_must_rest_before_the_next():
	var f := _fighter()
	for i in Sim.DASH_COOLDOWN:
		Sim.step(f, _dash_input(true), court)
	assert_eq(f.x, 100 + Sim.DASH_TICKS * Sim.SPEED * Sim.DASH_FACTOR + (Sim.DASH_COOLDOWN - Sim.DASH_TICKS) * Sim.SPEED)
	var before := f.x
	Sim.step(f, _dash_input(true), court)
	assert_eq(f.x - before, Sim.SPEED * Sim.DASH_FACTOR, "a new dash once rested")


func test_the_dash_travels_in_snapshots():
	var f := _fighter()
	Sim.step(f, _dash_input(true), court)
	var copy := Fighter.from_array(f.to_array())
	assert_eq(copy.dash_ticks, f.dash_ticks)
	assert_eq(copy.dash_cooldown, f.dash_cooldown)
	assert_true(Sim.sanitize({"dash": true}).dash)
