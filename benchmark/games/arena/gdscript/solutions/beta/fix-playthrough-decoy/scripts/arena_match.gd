class_name ArenaMatch
extends RefCounted
## The rules of a match, with no networking and no nodes: four slots, each held by a player or a bot, fight rounds of
## last-glimmer-standing on the courts in turn, and the first slot to win TARGET rounds wins the match. The server runs
## the true match; each client keeps one loaded from snapshots (load_snapshot) for drawing and for its bot.

enum State { WARMUP, ROUND, INTERMISSION, OVER }

const SLOTS := 4
## Rounds a slot must win to take the match.
const TARGET := 3
const HP := 5
const DAMAGE := 1
## Ticks before the first round, between rounds, and showing a finished match (a looping server then starts the next).
const WARMUP_TICKS := 30
const INTERMISSION_TICKS := 45
const OVER_TICKS := 150
## owners[] value of a slot played by a bot.
const BOT := 0
const STATE_NAMES := ["warmup", "round", "intermission", "over"]

var courts: Array[Court] = []
var court: Court
var tick := 0
var round_number := 0
var state := State.WARMUP
## Ticks spent in the current state.
var state_ticks := 0
var fighters: Array[Fighter] = []
## Per slot: BOT, or the peer id of the player who holds it.
var owners: Array[int] = []
## Per slot: rounds won in this match.
var scores: Array[int] = []
var winner := -1
## Matches finished since the server started.
var matches := 0
## Shots whose hit the shooter's client claimed otherwise than the server's trace found: lag, or a cheat.
var refused_claims := 0
## What happened since the last take_events(): shots, hits, outs, rounds, the end; snapshots carry them to clients.
var events: Array[Dictionary] = []


func _init(court_list: Array[Court] = []) -> void:
	courts = court_list
	court = courts[0] if not courts.is_empty() else Court.new()
	for slot in SLOTS:
		var f := Fighter.new()
		f.slot = slot
		fighters.append(f)
		owners.append(BOT)
		scores.append(0)


func state_name() -> String:
	return STATE_NAMES[state]


func is_bot(slot: int) -> bool:
	return owners[slot] == BOT


## A match point: some slot is one round from winning.
func is_match_point() -> bool:
	return state != State.OVER and scores.max() == TARGET - 1


func alive_slots() -> Array[int]:
	var alive: Array[int] = []
	for f in fighters:
		if f.alive:
			alive.append(f.slot)
	return alive


## Applies one slot's input for this tick. Inputs outside a round do nothing.
func apply(slot: int, input: Dictionary) -> void:
	if state != State.ROUND:
		return
	if Sim.step(fighters[slot], input, court):
		_fire(slot, input)


func _fire(slot: int, input: Dictionary) -> void:
	var shot := Sim.trace(court, fighters, slot)
	var claim := int(input.get("claim", -1))
	if claim != shot.target:
		# The client saw it otherwise (it draws others a little in the past, or it lies): the server's trace stands.
		refused_claims += 1
	var from := fighters[slot]
	events.append({"type": "shot", "slot": slot, "x": from.x, "y": from.y, "ex": shot.x, "ey": shot.y})
	if shot.target >= 0:
		_damage(slot, shot.target)


func _damage(by: int, target: int) -> void:
	var f := fighters[target]
	f.hp -= DAMAGE
	events.append({"type": "hit", "slot": target, "by": by})
	if f.hp <= 0:
		f.alive = false
		events.append({"type": "out", "slot": target, "by": by, "x": f.x, "y": f.y})
		_check_round_end()


## Moves the match on by one tick: the waits before and between rounds.
func advance() -> void:
	tick += 1
	state_ticks += 1
	if state == State.WARMUP and state_ticks >= WARMUP_TICKS:
		_begin_round()
	elif state == State.INTERMISSION and state_ticks >= INTERMISSION_TICKS:
		_begin_round()
	elif state == State.ROUND and state_ticks >= 20 * Sim.TICK_RATE:
		# A round that drags on ends: a lone survivor takes it, otherwise it is drawn.
		var alive := alive_slots()
		_end_round(alive[0] if alive.size() == 1 else -1)


## A new match with the same owners: scores back to 0, the first round after the warm-up.
func restart() -> void:
	round_number = 0
	winner = -1
	for slot in SLOTS:
		scores[slot] = 0
		fighters[slot].alive = false
	_set_state(State.WARMUP)


## Gives a slot to a player (a peer id) or back to a bot. Its score starts again: a newcomer does not inherit a
## leaver's rounds. Its glimmer leaves the round in play and comes back in the next one.
func set_owner(slot: int, owner: int) -> void:
	remove_fighter(slot)
	owners[slot] = owner
	scores[slot] = 0


## Takes a slot's glimmer out of the round in play (its player left, or a player took a bot's slot).
func remove_fighter(slot: int) -> void:
	var f := fighters[slot]
	if not f.alive:
		return
	f.alive = false
	events.append({"type": "gone", "slot": slot})


func _check_round_end() -> void:
	if state != State.ROUND:
		return
	var alive := alive_slots()
	if alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else -1)


func _end_round(round_winner: int) -> void:
	if round_winner >= 0:
		scores[round_winner] += 1
		print("[Match] round %d won by slot %d (%s)" % [round_number, round_winner, "-".join(scores.map(str))])
	else:
		print("[Match] round %d drawn" % round_number)
	events.append({"type": "round", "round": round_number, "winner": round_winner})
	if round_winner >= 0 and scores[round_winner] >= TARGET:
		winner = round_winner
		matches += 1
		print("[Match] over: slot %d wins %d rounds to %d" % [winner, scores[winner], _second_best()])
		events.append({"type": "over", "winner": winner})
		_set_state(State.OVER)
	else:
		_set_state(State.INTERMISSION)


func _second_best() -> int:
	var best := 0
	for slot in SLOTS:
		if slot != winner:
			best = maxi(best, scores[slot])
	return best


func _begin_round() -> void:
	round_number += 1
	court = courts[(round_number - 1) % courts.size()]
	for f in fighters:
		var spawn := court.spawns[(f.slot + round_number - 1) % court.spawns.size()]
		f.x = spawn.x
		f.y = spawn.y
		f.ax = court.width / 2 - spawn.x
		f.ay = court.height / 2 - spawn.y
		f.hp = HP
		f.alive = true
		f.cooldown = 0
		f.dash_ticks = 0
		f.dash_cooldown = 0
	print("[Match] round %d started on %s" % [round_number, court.id])
	events.append({"type": "start", "round": round_number})
	_set_state(State.ROUND)


func _set_state(next: State) -> void:
	state = next
	state_ticks = 0


func take_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


func court_by_id(court_id: String) -> Court:
	for c in courts:
		if c.id == court_id:
			return c
	return court


## What a client needs to draw the match and predict its own glimmer.
func snapshot() -> Dictionary:
	return {
		"tick": tick, "round": round_number, "court": court.id, "state": int(state), "state_ticks": state_ticks,
		"scores": scores.duplicate(), "owners": owners.duplicate(), "winner": winner,
		"fighters": fighters.map(func(f: Fighter) -> Array: return f.to_array()),
	}


func load_snapshot(snap: Dictionary) -> void:
	tick = int(snap.tick)
	round_number = int(snap.round)
	court = court_by_id(str(snap.court))
	state = int(snap.state) as State
	state_ticks = int(snap.state_ticks)
	winner = int(snap.winner)
	for slot in SLOTS:
		scores[slot] = int(snap.scores[slot])
		owners[slot] = int(snap.owners[slot])
		fighters[slot] = Fighter.from_array(snap.fighters[slot])
