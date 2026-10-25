extends GutTest
## Hidden check for the beta's fix-playthrough: a glimmer that leaves the round (its player left, or a newcomer took a
## bot's slot) ends the round the moment one is left standing, and at match point that ends the match.

var server: ArenaServer
var link: SimLink
var leaver: ArenaClient


func before_each():
	var courts := Court.load_all()
	server = ArenaServer.new(courts, 3)
	server.bots_enabled = false
	link = SimLink.new(server)
	leaver = ArenaClient.new(courts)
	link.join(leaver, 11)
	for i in ArenaMatch.WARMUP_TICKS + 2:
		_tick()


func _tick() -> void:
	link.pump()
	server.tick()
	link.pump()
	link.advance()


func _out(slot: int) -> void:
	for i in ArenaMatch.HP:
		server.arena._damage(3, slot)


func test_hidden_the_last_two_and_one_leaves():
	assert_eq(server.slot_of(11), 0)
	_out(1)
	_out(2)
	link.leave(11)
	assert_eq(server.arena.state, ArenaMatch.State.INTERMISSION, "the round is over at once")
	assert_eq(server.arena.scores[3], 1, "the one left standing wins it")


func test_hidden_leaving_at_match_point_ends_the_match():
	server.arena.scores[3] = ArenaMatch.TARGET - 1
	_out(1)
	_out(2)
	link.leave(11)
	assert_eq(server.arena.state, ArenaMatch.State.OVER)
	assert_eq(server.arena.winner, 3)


func test_hidden_a_newcomer_taking_the_last_rivals_slot_ends_the_round():
	_out(0)
	_out(1)
	# Slots 2 and 3 are bots, the last two standing; a newcomer takes slot 1, which is out, so nothing changes...
	var newcomer := ArenaClient.new(Court.load_all())
	link.join(newcomer, 12)
	assert_eq(server.arena.state, ArenaMatch.State.ROUND)
	# ...until the leaver goes too and a second newcomer takes slot 2, a standing bot's: slot 3 is left alone.
	link.leave(11)
	var second := ArenaClient.new(Court.load_all())
	link.join(second, 13)
	assert_eq(server.slot_of(13), 0)
	link.leave(12)
	var third := ArenaClient.new(Court.load_all())
	assert_eq(link.join(third, 14), 1)
	assert_eq(server.arena.state, ArenaMatch.State.ROUND)
	var fourth := ArenaClient.new(Court.load_all())
	assert_eq(link.join(fourth, 15), 2)
	assert_eq(server.arena.state, ArenaMatch.State.INTERMISSION)
	assert_eq(server.arena.scores[3], 1)


func test_hidden_the_next_round_follows():
	_out(1)
	_out(2)
	link.leave(11)
	for i in ArenaMatch.INTERMISSION_TICKS + 2:
		_tick()
	assert_eq(server.arena.round_number, 2)
	assert_eq(server.arena.alive_slots().size(), 4)
