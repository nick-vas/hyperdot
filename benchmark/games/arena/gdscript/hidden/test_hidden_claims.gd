extends GutTest
## Hidden check for the prototype's fix-bug: hits are decided by the server's own trace. Whatever slot a client claims
## to have hit, a pillar still stops the shot and a glimmer the shot never reached keeps its health.

var server: ArenaServer
var link: SimLink
var client: ArenaClient


func before_each():
	var courts := Court.load_all()
	server = ArenaServer.new(courts, 5)
	server.bots_enabled = false
	link = SimLink.new(server)
	client = ArenaClient.new(courts)
	link.join(client, 10)
	for i in ArenaMatch.WARMUP_TICKS + 2:
		_tick()


func _tick() -> void:
	link.pump()
	server.tick()
	link.pump()
	link.advance()


func _place(slot: int, x: int, y: int) -> void:
	server.arena.fighters[slot].x = x
	server.arena.fighters[slot].y = y


# An input as a client sends it, straight to the server, with whatever claim it likes.
func _send(ax: int, ay: int, fire: bool, claim: int) -> void:
	client.seq += 1
	server.receive(10, {"t": "input", "inputs": [{"seq": client.seq, "mx": 0, "my": 0, "ax": ax, "ay": ay, "fire": fire, "claim": claim}]})
	_tick()


# A shot, then the inputs that let the cooldown run out.
func _shoot(ax: int, ay: int, claim: int) -> void:
	_send(ax, ay, true, claim)
	for i in Sim.FIRE_COOLDOWN + 1:
		_send(0, 0, false, -1)


func test_hidden_a_claim_through_a_pillar_scores_nothing():
	# The Cinder Pit's top pillar (x 570 to 630, y 0 to 170) stands between them.
	_place(0, 400, 100)
	_place(1, 800, 100)
	_shoot(1, 0, 1)
	assert_eq(server.arena.fighters[1].hp, ArenaMatch.HP)


func test_hidden_a_claim_on_someone_out_of_line_scores_nothing():
	_place(0, 100, 220)
	_place(2, 400, 220)
	_place(3, 300, 560)
	_shoot(1, 0, 3)
	assert_eq(server.arena.fighters[3].hp, ArenaMatch.HP, "never in the line of fire")
	assert_eq(server.arena.fighters[2].hp, ArenaMatch.HP - 1, "the one the shot reached")


func test_hidden_claims_cannot_knock_out_from_across_the_pit():
	_place(0, 80, 80)
	_place(1, 1120, 560)
	for i in ArenaMatch.HP + 1:
		_shoot(0, -1, 1)
	assert_true(server.arena.fighters[1].alive)
	assert_eq(server.arena.scores, [0, 0, 0, 0])


func test_hidden_an_honest_shot_in_the_open_hits():
	_place(0, 100, 220)
	_place(1, 400, 220)
	_shoot(1, 0, 1)
	assert_eq(server.arena.fighters[1].hp, ArenaMatch.HP - 1)
	_shoot(1, 0, -1)
	assert_eq(server.arena.fighters[1].hp, ArenaMatch.HP - 2, "no claim needed")
