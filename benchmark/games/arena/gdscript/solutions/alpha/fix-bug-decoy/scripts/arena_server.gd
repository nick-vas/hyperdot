class_name ArenaServer
extends RefCounted
## The authoritative server, with no transport of its own: peers join and leave, their inputs come in with receive(),
## and every SNAPSHOT_EVERY ticks each peer gets a snapshot through `send` (peer id, message). The game runs it in-process
## over a SimLink for local play; NetSession carries it over ENet for hosting and as the dedicated server soak runs.
## Players hold slots; bots play the rest, so a match is always four glimmers.

const SNAPSHOT_EVERY := 2
## A peer's queue beyond this many inputs is worked down two a tick, so a burst after a stall does not add lag for good.
const BACKLOG := 4
## Inputs kept per peer in its log.
const LOG_SIZE := 64

var arena: ArenaMatch
var bots: Array[Bot] = []
## (peer: int, message: Dictionary) -> void
var send: Callable
## Off in tests that want the bots' glimmers to stand still.
var bots_enabled := true
## A dedicated server starts the next match when one is over.
var loop_matches := false

## Peer id -> its slot.
var _peers := {}
## Peer id -> inputs received and not applied yet, oldest first.
var _queues := {}
## Peer id -> the sequence number of its last applied input (acknowledged in its snapshots).
var _last_seq := {}
## Peer id -> its last LOG_SIZE applied inputs, so a desync or cheat report can replay what the server did.
var _input_log := {}


func _init(courts: Array[Court], match_seed := 1) -> void:
	arena = ArenaMatch.new(courts)
	for slot in ArenaMatch.SLOTS:
		bots.append(Bot.new(slot, match_seed * 7919 + slot))


func peer_count() -> int:
	return _peers.size()


func slot_of(peer: int) -> int:
	return int(_peers.get(peer, -1))


## The most records the server keeps for any one kind of per-peer state; never more than the peers connected.
func record_count() -> int:
	return maxi(maxi(_peers.size(), _queues.size()), maxi(_last_seq.size(), _input_log.size()))


## A peer connected: it takes the first slot a bot holds, or is told the pit is full. Returns its slot, or -1.
func peer_joined(peer: int) -> int:
	if _peers.has(peer):
		return slot_of(peer)
	var slot := -1
	for s in ArenaMatch.SLOTS:
		if arena.is_bot(s):
			slot = s
			break
	if slot < 0:
		_send(peer, {"t": "full"})
		return -1
	_peers[peer] = slot
	_queues[peer] = []
	_last_seq[peer] = 0
	_input_log[peer] = []
	arena.set_owner(slot, peer)
	print("[Net] peer %d joined slot %d" % [peer, slot])
	_send(peer, {"t": "welcome", "slot": slot, "snap": arena.snapshot()})
	return slot


## A peer disconnected (or timed out): its slot goes back to a bot, and nothing of it is kept.
func peer_left(peer: int) -> void:
	if not _peers.has(peer):
		return
	var slot := slot_of(peer)
	print("[Net] peer %d left slot %d" % [peer, slot])
	arena.remove_fighter(slot)
	_peers.erase(peer)
	_queues.erase(peer)
	_last_seq.erase(peer)
	_input_log.erase(peer)


## A message from a peer. Only inputs are accepted, each sequence number once, in order.
func receive(peer: int, message: Variant) -> void:
	if not _peers.has(peer) or typeof(message) != TYPE_DICTIONARY or message.get("t", "") != "input":
		return
	var inputs: Variant = message.get("inputs", [])
	if typeof(inputs) != TYPE_ARRAY:
		return
	var queue: Array = _queues[peer]
	for raw: Variant in inputs:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var input := Sim.sanitize(raw)
		var newest: int = queue.back().seq if not queue.is_empty() else _last_seq[peer]
		if input.seq > newest:
			queue.append(input)


## One server tick: every slot's input applied, the match moved on, snapshots out. A player whose input has not
## arrived is left as it is, not given a made-up one.
func tick() -> void:
	for slot in ArenaMatch.SLOTS:
		var input := _next_input(slot)
		if not input.is_empty():
			arena.apply(slot, input)
		var owner := arena.owners[slot]
		if owner != ArenaMatch.BOT and _queues.has(owner) and _queues[owner].size() > BACKLOG:
			arena.apply(slot, _next_input(slot))
	arena.advance()
	if loop_matches and arena.state == ArenaMatch.State.OVER and arena.state_ticks >= ArenaMatch.OVER_TICKS:
		arena.restart()
	_trim_logs()
	if arena.tick % SNAPSHOT_EVERY == 0:
		_broadcast(arena.take_events())


func _next_input(slot: int) -> Dictionary:
	var owner := arena.owners[slot]
	if owner == ArenaMatch.BOT:
		return bots[slot].decide(arena) if bots_enabled else Sim.idle()
	var queue: Array = _queues.get(owner, [])
	if queue.is_empty():
		# Starved: nothing is applied this tick (not even its timers run), so the client's prediction still holds.
		return {}
	var input: Dictionary = queue.pop_front()
	_last_seq[owner] = input.seq
	_input_log[owner].append(input)
	return input


func _trim_logs() -> void:
	for peer: int in _input_log:
		var entries: Array = _input_log[peer]
		if entries.size() > LOG_SIZE:
			entries.pop_front()


func _broadcast(events: Array[Dictionary]) -> void:
	var snap := arena.snapshot()
	snap.events = events
	for peer: int in _peers:
		_send(peer, {"t": "snap", "ack": _last_seq[peer], "slot": _peers[peer], "snap": snap})


func _send(peer: int, message: Dictionary) -> void:
	if send.is_valid():
		send.call(peer, message)
