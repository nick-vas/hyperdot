class_name ArenaClient
extends RefCounted
## A player's side of the netcode, with no transport of its own. Its own glimmer is predicted: each input is applied at
## once with the server's own Sim.step and kept until a snapshot acknowledges it. A snapshot is the truth as of the last
## input the server applied, so the client takes it and replays the inputs the server has not seen yet; with the same
## code on both sides that lands exactly where the prediction was, and nothing visibly corrects. Other glimmers are drawn
## INTERP_TICKS behind the newest snapshot, between the two snapshots around that moment, so they move evenly.

## Ticks other glimmers are shown in the past: two snapshot intervals and a little more.
const INTERP_TICKS := 5
## Each input message repeats the newest inputs not yet acknowledged, so one lost packet loses nothing.
const REDUNDANT := 3
## Snapshots kept for interpolation.
const HISTORY := 8

## (message: Dictionary) -> void
var send: Callable
var slot := -1
var full := false
## The match as the last snapshot told it, with this client's glimmer replaced by its prediction.
var view: ArenaMatch
var predicted: Fighter
var seq := 0
## Inputs sent and not acknowledged yet, oldest first.
var pending: Array[Dictionary] = []
## How many snapshots moved the predicted glimmer, and by how much the last one did (pixels).
var corrections := 0
var last_correction := 0.0
var snapshots := 0
## Events from the server not taken by the game yet.
var events: Array[Dictionary] = []

var _history: Array[Dictionary] = []
var _render_tick := 0.0


func _init(courts: Array[Court]) -> void:
	view = ArenaMatch.new(courts)


func is_playing() -> bool:
	return slot >= 0 and predicted != null


## A message from the server.
func receive(message: Variant) -> void:
	if typeof(message) != TYPE_DICTIONARY:
		return
	match str(message.get("t", "")):
		"welcome":
			slot = int(message.slot)
			pending.clear()
			_take_snapshot(message.snap, seq)
		"snap":
			if slot >= 0:
				_take_snapshot(message.snap, int(message.ack))
		"full":
			full = true


func _take_snapshot(snap: Dictionary, ack: int) -> void:
	snapshots += 1
	var round_before := view.round_number
	view.load_snapshot(snap)
	for event: Dictionary in snap.get("events", []):
		events.append(event)
	_history.append({"tick": view.tick, "fighters": view.fighters.duplicate()})
	if _history.size() > HISTORY:
		_history.pop_front()
	# The clock others are drawn at follows the snapshots: set on the first, and again whenever it drifts (a stall,
	# a burst), so they are always INTERP_TICKS behind the newest.
	if snapshots == 1 or absf(_render_tick - (view.tick - INTERP_TICKS)) > 3.0:
		_render_tick = view.tick - INTERP_TICKS
	var before: Fighter = predicted
	while not pending.is_empty() and int(pending[0].seq) <= ack:
		pending.pop_front()
	predicted = view.fighters[slot].copy()
	if view.state == ArenaMatch.State.ROUND:
		for input in pending:
			Sim.step(predicted, input, view.court)
	if before != null and view.round_number == round_before and view.state == ArenaMatch.State.ROUND:
		last_correction = before.position().distance_to(predicted.position())
		if last_correction > 0.01:
			corrections += 1
	view.fighters[slot] = predicted


## One client tick: the player's input, applied at once and sent. Returns true when it fires (the game shows the shot
## at once; the server decides whether it hits).
func step(mx: int, my: int, ax: int, ay: int, fire: bool) -> bool:
	_render_tick += 1.0
	if not is_playing():
		return false
	seq += 1
	var input := {"seq": seq, "mx": mx, "my": my, "ax": ax, "ay": ay, "fire": fire, "claim": -1}
	var fired := false
	if view.state == ArenaMatch.State.ROUND:
		fired = Sim.step(predicted, input, view.court)
	pending.append(input)
	if send.is_valid():
		send.call({"t": "input", "inputs": pending.slice(maxi(pending.size() - REDUNDANT, 0))})
	return fired


## The fighters as this screen shows them: its own predicted, the others interpolated in the past.
func shown_fighters() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for s in ArenaMatch.SLOTS:
		out.append(predicted if s == slot and predicted != null else _interpolated(s))
	return out


func _interpolated(s: int) -> Fighter:
	if _history.is_empty():
		return view.fighters[s]
	var newest: Fighter = _history.back().fighters[s]
	for i in range(_history.size() - 1, 0, -1):
		var a: Dictionary = _history[i - 1]
		var b: Dictionary = _history[i]
		if a.tick <= _render_tick and _render_tick <= b.tick:
			var fa: Fighter = a.fighters[s]
			var fb: Fighter = b.fighters[s]
			var shown := fb.copy()
			if fa.alive and fb.alive and b.tick > a.tick:
				var t: float = (_render_tick - a.tick) / float(b.tick - a.tick)
				shown.x = int(roundf(lerpf(fa.x, fb.x, t)))
				shown.y = int(roundf(lerpf(fa.y, fb.y, t)))
			return shown
	return newest
