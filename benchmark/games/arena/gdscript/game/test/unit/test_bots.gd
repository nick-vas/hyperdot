extends GutTest
## Bots: a match of four bots ends, on both courts, and replays for a seed.

func _play_out(match_seed: int, max_ticks := 9000) -> ArenaServer:
	var server := ArenaServer.new(Court.load_all(), match_seed)
	for i in max_ticks:
		server.tick()
		if server.arena.state == ArenaMatch.State.OVER:
			break
	return server


func test_a_bot_match_ends_on_a_score():
	var server := _play_out(1)
	assert_eq(server.arena.state, ArenaMatch.State.OVER)
	assert_eq(server.arena.scores[server.arena.winner], ArenaMatch.TARGET)
	assert_gte(server.arena.round_number, ArenaMatch.TARGET)


func test_bot_matches_take_under_three_minutes():
	for match_seed in [2, 3, 4]:
		var server := _play_out(match_seed)
		assert_eq(server.arena.state, ArenaMatch.State.OVER, "seed %d ends" % match_seed)
		assert_between(server.arena.tick, 15 * Sim.TICK_RATE, 150 * Sim.TICK_RATE, "seed %d" % match_seed)


func test_a_seed_replays_the_same_match():
	var a := _play_out(7)
	var b := _play_out(7)
	assert_eq(a.arena.tick, b.arena.tick)
	assert_eq(a.arena.scores, b.arena.scores)
	assert_eq(a.arena.winner, b.arena.winner)
