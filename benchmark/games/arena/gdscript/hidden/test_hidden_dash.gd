extends GutTest
## Hidden check for the prototype's add-feature: the dash. Three times the speed for 5 ticks from the press, no new dash
## for 45 ticks from the press, and the same on the server and in a client's prediction, so a dash online corrects nothing.

var court: Court


func before_each():
	court = Court.load_all()[0]


func _fighter(x: int, y: int) -> Fighter:
	var f := Fighter.new()
	f.x = x
	f.y = y
	f.alive = true
	return f


func _dash_input(mx: int, dash: bool) -> Dictionary:
	var input := Sim.idle()
	input.mx = mx
	input["dash"] = dash
	return input


func _xs(presses: Array) -> Array:
	var f := _fighter(100, 220)
	var xs := []
	for press: bool in presses:
		Sim.step(f, _dash_input(1, press), court)
		xs.append(f.x)
	return xs


func test_hidden_a_dash_is_three_times_as_fast_for_five_ticks():
	var presses := [true, false, false, false, false, false, false]
	assert_eq(_xs(presses), [124, 148, 172, 196, 220, 228, 236])


func test_hidden_a_dash_waits_45_ticks_from_the_press():
	var presses := []
	for i in 46:
		presses.append(true)
	var xs := _xs(presses)
	assert_eq(xs[5] - xs[4], 8, "no second dash at tick 6")
	assert_eq(xs[44] - xs[43], 8, "still resting at tick 45")
	assert_eq(xs[45] - xs[44], 24, "a new dash at tick 46")


func test_hidden_a_dash_without_moving_goes_nowhere():
	var f := _fighter(100, 220)
	Sim.step(f, _dash_input(0, true), court)
	assert_eq(f.x, 100)


func test_hidden_a_dash_stops_at_a_pillar():
	var f := _fighter(500, 320)
	for i in 3:
		Sim.step(f, _dash_input(1, i == 0), court)
	assert_eq(f.x, 540 - Court.HALF)


func test_hidden_a_dash_online_needs_no_correction():
	var courts := Court.load_all()
	var server := ArenaServer.new(courts, 5)
	server.bots_enabled = false
	var link := SimLink.new(server, 3)
	var client := ArenaClient.new(courts)
	link.join(client, 10)
	var script_steps := []
	for i in 120:
		script_steps.append(i == 50 or i == 100)
	for i in ArenaMatch.WARMUP_TICKS + 2:
		_online_tick(client, link, server)
	server.arena.fighters[0].x = 100
	server.arena.fighters[0].y = 220
	for i in 10:
		_online_tick(client, link, server)
	client.corrections = 0
	for press: bool in script_steps:
		# The client takes the dash as step()'s sixth argument.
		client.call("step", 1, 0, 1, 0, false, press)
		link.pump()
		server.tick()
		link.pump()
		link.advance()
	for i in 10:
		_online_tick(client, link, server)
	assert_eq(client.corrections, 0)
	assert_eq(client.predicted.position(), server.arena.fighters[0].position())
	assert_eq(server.arena.fighters[0].x, 1200 - Court.HALF, "two dashes carried it to the far edge")


func _online_tick(client: ArenaClient, link: SimLink, server: ArenaServer) -> void:
	client.step(0, 0, 1, 0, false)
	link.pump()
	server.tick()
	link.pump()
	link.advance()
