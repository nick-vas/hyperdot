class_name SimLink
extends RefCounted
## Clients and a server in one process, with a delay each way in ticks and an optional jitter from its own seeded
## generator. Local play runs over it with no delay; --lag=MS and the netcode tests give it one, since ENet has no lag
## of its own to simulate. Every message is turned into bytes and back, as the wire would, so nothing is shared.

var server: ArenaServer
## Ticks each way, and the most a message may arrive later than that (never earlier, never out of order).
var delay_ticks := 0
var jitter_ticks := 0
var rng := RandomNumberGenerator.new()

var _tick := 0
var _clients := {}           # peer id -> ArenaClient
var _to_server: Array = []   # { at, peer, bytes }
var _to_client: Array = []   # { at, peer, bytes }
var _last_at := {}           # "s<peer>" / "c<peer>" -> the arrival tick of the newest message, kept in order


func _init(link_server: ArenaServer, delay := 0, jitter := 0, link_seed := 1) -> void:
	server = link_server
	delay_ticks = delay
	jitter_ticks = jitter
	rng.seed = link_seed
	server.send = deliver


## Delay in ticks for a round trip of `ms` milliseconds.
static func ticks_for_ms(ms: int) -> int:
	return int(roundf(ms / 2.0 * Sim.TICK_RATE / 1000.0))


## Connects a client as `peer`; the server takes it in at once, its welcome arrives after the delay.
func join(client: ArenaClient, peer: int) -> int:
	_clients[peer] = client
	# A bound method, not a lambda: a lambda would hold the link, and the link holds the client, a cycle never freed.
	client.send = _from_client.bind(peer)
	return server.peer_joined(peer)


## Disconnects a client: the server forgets it now, and whatever was on its way is lost.
func leave(peer: int) -> void:
	if not _clients.has(peer):
		return
	var client: ArenaClient = _clients[peer]
	client.send = Callable()
	_clients.erase(peer)
	_to_server = _to_server.filter(func(m: Dictionary) -> bool: return m.peer != peer)
	_to_client = _to_client.filter(func(m: Dictionary) -> bool: return m.peer != peer)
	_last_at.erase("s%d" % peer)
	_last_at.erase("c%d" % peer)
	server.peer_left(peer)


func has_peer(peer: int) -> bool:
	return _clients.has(peer)


func _from_client(message: Dictionary, peer: int) -> void:
	_queue(_to_server, peer, message, "s%d" % peer)


## A message from the server to a client of this link.
func deliver(peer: int, message: Dictionary) -> void:
	if _clients.has(peer):
		_queue(_to_client, peer, message, "c%d" % peer)


func _queue(queue: Array, peer: int, message: Dictionary, lane: String) -> void:
	var at := _tick + delay_ticks + (rng.randi_range(0, jitter_ticks) if jitter_ticks > 0 else 0)
	at = maxi(at, int(_last_at.get(lane, 0)))
	_last_at[lane] = at
	queue.append({"at": at, "peer": peer, "bytes": var_to_bytes(message)})


## Delivers what is due by now: inputs to the server, snapshots to the clients.
func pump() -> void:
	for m: Dictionary in _due(_to_server):
		server.receive(m.peer, bytes_to_var(m.bytes))
	for m: Dictionary in _due(_to_client):
		if _clients.has(m.peer):
			_clients[m.peer].receive(bytes_to_var(m.bytes))


# Takes the messages due by now out of a queue, in the order they were sent.
func _due(queue: Array) -> Array:
	var due := queue.filter(func(m: Dictionary) -> bool: return m.at <= _tick)
	if not due.is_empty():
		var later := queue.filter(func(m: Dictionary) -> bool: return m.at > _tick)
		queue.clear()
		queue.append_array(later)
	return due


## The link's clock: one tick later.
func advance() -> void:
	_tick += 1
