class_name Autopilot
extends RefCounted
## --autoplay: a bot plays the player's glimmer through the player's own client, from what that client sees, and a
## guest joins the same match as a second client on the link, played by another bot. The guest walks out whenever it is
## one of the last two standing with one health left, and comes back a little later, so every bot run also covers
## players leaving and joining in the middle of a match.

const GUEST_PEER := 2
## Ticks the guest stays away after leaving.
const AWAY_TICKS := 60

var game: Node
var guest: ArenaClient
var leaves := 0

var _bot: Bot
var _guest_bot: Bot
var _away := 0
var _seed := 1


func _init(game_node: Node, run_seed: int) -> void:
	game = game_node
	_seed = run_seed
	_bot = Bot.new(0, run_seed * 31 + 1)
	_guest_bot = Bot.new(1, run_seed * 31 + 2)
	if game.link != null:
		_join_guest()


## The player's input for this tick, from the player's bot.
func player_input() -> Dictionary:
	var client: ArenaClient = game.client
	if not client.is_playing():
		return Sim.idle()
	_bot.slot = client.slot
	return _bot.decide(client.view, client.predicted)


## The guest's tick: play, walk out, or come back.
func tick() -> void:
	if game.link == null:
		return
	if guest == null:
		_away -= 1
		if _away <= 0:
			_join_guest()
		return
	if not guest.is_playing():
		return
	_guest_bot.slot = guest.slot
	var input := _guest_bot.decide(guest.view, guest.predicted)
	guest.step(input.mx, input.my, input.ax, input.ay, input.fire, input.dash)
	guest.events.clear()
	if _losing(guest):
		leaves += 1
		game.link.leave(GUEST_PEER)
		guest = null
		_away = AWAY_TICKS


func _losing(c: ArenaClient) -> bool:
	var arena := c.view
	return arena.state == ArenaMatch.State.ROUND and c.predicted.alive and c.predicted.hp == 1 and arena.alive_slots().size() == 2


func _join_guest() -> void:
	guest = ArenaClient.new(game.courts)
	game.link.join(guest, GUEST_PEER)


func stop() -> void:
	if guest != null and game.link != null:
		game.link.leave(GUEST_PEER)
	guest = null
