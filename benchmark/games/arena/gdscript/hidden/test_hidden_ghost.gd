extends GutTest
## Hidden check for the alpha's fix-bug: a player who leaves takes their glimmer with them. It leaves the round at once,
## a bot takes the slot and plays it from the next round, and nothing of the player stays on the server.

var courts: Array[Court]
var server: ArenaServer
var link: SimLink
var stayer: ArenaClient
var leaver: ArenaClient


func before_each():
	courts = Court.load_all()
	server = ArenaServer.new(courts, 9)
	link = SimLink.new(server)
	stayer = ArenaClient.new(courts)
	leaver = ArenaClient.new(courts)
	link.join(stayer, 10)
	link.join(leaver, 11)
	for i in ArenaMatch.WARMUP_TICKS + 2:
		_tick()


func _tick() -> void:
	for c: ArenaClient in [stayer, leaver]:
		if link.has_peer(10 if c == stayer else 11):
			c.step(0, 0, 1, 0, false)
	link.pump()
	server.tick()
	link.pump()
	link.advance()


func test_hidden_the_leaver_leaves_the_round_at_once():
	assert_eq(server.slot_of(11), 1)
	link.leave(11)
	assert_false(server.arena.fighters[1].alive, "no ghost left standing")
	assert_true(server.arena.is_bot(1), "a bot holds the slot")
	assert_eq(server.arena.scores[1], 0)
	_tick()
	_tick()
	var snap: Dictionary = server.arena.snapshot()
	assert_false(11 in snap.owners, "the snapshot no longer names the leaver")


func test_hidden_a_bot_plays_the_slot_from_the_next_round():
	link.leave(11)
	for slot in [2, 3]:
		for i in ArenaMatch.HP:
			server.arena._damage(0, slot)
	assert_eq(server.arena.state, ArenaMatch.State.INTERMISSION, "the round ended without the ghost to shoot")
	for i in ArenaMatch.INTERMISSION_TICKS + 2:
		_tick()
	assert_eq(server.arena.round_number, 2)
	var f: Fighter = server.arena.fighters[1]
	assert_true(f.alive)
	var start := f.position()
	for i in 60:
		_tick()
	assert_ne(server.arena.fighters[1].position(), start, "the bot moves the slot's glimmer")


func test_hidden_the_leaver_can_come_back():
	link.leave(11)
	var back := ArenaClient.new(courts)
	assert_eq(link.join(back, 12), 1, "the bot's slot is free to take")
	assert_eq(server.peer_count(), 2)
