extends GutTest
## Hidden check for the beta's fix-bug: on a connection with a round trip of 100 ms or more, a player's own glimmer moves
## a whole step every tick it is told to, never back, and no snapshot moves it: the prediction is reconciled, not reset.

var courts: Array[Court]
var server: ArenaServer
var link: SimLink
var client: ArenaClient


func _setup(delay: int, jitter: int) -> void:
	courts = Court.load_all()
	server = ArenaServer.new(courts, 5)
	server.bots_enabled = false
	link = SimLink.new(server, delay, jitter, 11)
	client = ArenaClient.new(courts)
	link.join(client, 10)
	for i in ArenaMatch.WARMUP_TICKS + 2 * delay + jitter + 4:
		_tick(0, 0)
	server.arena.fighters[0].x = 100
	server.arena.fighters[0].y = 220
	for i in 2 * delay + jitter + 4:
		_tick(0, 0)


func _tick(mx: int, my: int) -> void:
	client.step(mx, my, 1, 0, false)
	link.pump()
	server.tick()
	link.pump()
	link.advance()


# Moves right for `ticks`, then down, recording how far the predicted glimmer moved on each tick.
func _steps(ticks: int) -> Array[float]:
	var steps: Array[float] = []
	var last := client.predicted.position()
	for i in ticks:
		_tick(1, 0) if i < ticks / 2 else _tick(0, 1)
		var now := client.predicted.position()
		steps.append(now.distance_to(last))
		last = now
	return steps


func test_hidden_100_ms_moves_a_whole_step_every_tick():
	_setup(SimLink.ticks_for_ms(100), 0)
	var corrections := client.corrections
	var steps := _steps(60)
	assert_eq(steps.min(), float(Sim.SPEED), "never held back")
	assert_eq(steps.max(), float(Sim.SPEED), "never thrown forward or back")
	assert_eq(client.corrections, corrections, "no snapshot moved it")


func test_hidden_250_ms_with_jitter_corrects_nothing():
	_setup(SimLink.ticks_for_ms(250), 2)
	var corrections := client.corrections
	var steps := _steps(60)
	assert_eq(steps.min(), float(Sim.SPEED))
	assert_eq(steps.max(), float(Sim.SPEED))
	assert_eq(client.corrections, corrections)


func test_hidden_it_ends_where_the_server_says():
	_setup(SimLink.ticks_for_ms(150), 1)
	_steps(40)
	for i in 20:
		_tick(0, 0)
	assert_eq(client.predicted.position(), server.arena.fighters[0].position())
