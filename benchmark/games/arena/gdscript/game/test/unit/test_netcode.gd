extends GutTest
## The netcode core in one process: a server, clients on a SimLink, bots in the free slots.

var courts: Array[Court]
var server: ArenaServer
var link: SimLink


func before_each():
	courts = Court.load_all()
	server = ArenaServer.new(courts, 5)
	server.bots_enabled = false
	link = SimLink.new(server)


func _tick(clients: Array, mx := 1, my := 0) -> void:
	for c: ArenaClient in clients:
		c.step(mx, my, 1, 0, false)
	link.pump()
	server.tick()
	link.pump()
	link.advance()


func _to_round(clients: Array) -> void:
	for i in ArenaMatch.WARMUP_TICKS + 2:
		_tick(clients, 0, 0)


func test_a_player_takes_the_first_bot_slot():
	var client := ArenaClient.new(courts)
	assert_eq(link.join(client, 10), 0)
	link.pump()
	assert_eq(client.slot, 0)
	assert_false(server.arena.is_bot(0))
	assert_true(server.arena.is_bot(1))


func test_a_fifth_player_is_told_the_pit_is_full():
	for peer in [10, 11, 12, 13]:
		link.join(ArenaClient.new(courts), peer)
	var late := ArenaClient.new(courts)
	assert_eq(link.join(late, 14), -1)
	link.pump()
	assert_true(late.full)


func test_the_client_follows_the_server_with_no_delay():
	var client := ArenaClient.new(courts)
	link.join(client, 10)
	_to_round([client])
	for i in 20:
		_tick([client], 1, 0)
	var truth := server.arena.fighters[0]
	assert_eq(client.predicted.position(), truth.position())
	assert_eq(client.corrections, 0)


func test_a_lagging_client_ends_where_the_server_says():
	link.delay_ticks = 3
	var client := ArenaClient.new(courts)
	link.join(client, 10)
	for i in 10:
		_tick([client], 0, 0)
	_to_round([client])
	for i in 30:
		_tick([client], 1, 1)
	for i in 12:
		_tick([client], 0, 0)
	assert_eq(client.predicted.position(), server.arena.fighters[0].position())
	assert_lte(client.pending.size(), 2 * link.delay_ticks + 1, "only the inputs still on their way")


func test_the_server_keeps_its_own_counsel_on_hits():
	var client := ArenaClient.new(courts)
	link.join(client, 10)
	_to_round([client])
	var refused := server.arena.refused_claims
	client.send.call({"t": "input", "inputs": [{"seq": client.seq + 1, "mx": 0, "my": 0, "ax": 1, "ay": 0, "fire": true, "claim": 3}]})
	link.pump()
	server.tick()
	assert_eq(server.arena.refused_claims, refused + 1)


func test_a_leaver_gives_the_slot_back_to_a_bot():
	var client := ArenaClient.new(courts)
	link.join(client, 10)
	_to_round([client])
	link.leave(10)
	assert_true(server.arena.is_bot(0))
	assert_eq(server.slot_of(10), -1)
	assert_eq(server.record_count(), 0)


func test_another_players_glimmer_moves_evenly_on_a_lagging_screen():
	link.delay_ticks = 3
	var mover := ArenaClient.new(courts)
	var watcher := ArenaClient.new(courts)
	link.join(mover, 10)
	link.join(watcher, 11)
	_to_round([mover, watcher])
	var last := watcher.shown_fighters()[0].position()
	var steps: Array[float] = []
	for i in 30:
		mover.step(1, 0, 1, 0, false)
		watcher.step(0, 0, 1, 0, false)
		link.pump()
		server.tick()
		link.pump()
		link.advance()
		var now := watcher.shown_fighters()[0].position()
		steps.append(now.distance_to(last))
		last = now
	assert_lte(steps.slice(12).max(), Sim.SPEED + 1.0, "never more than a tick's step at once")
	assert_gt(steps.slice(12).min(), 0.0, "never standing still between snapshots")
