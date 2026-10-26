class_name NetSession
extends Node
## Carries the netcode over ENet: a server (hosted or dedicated) or a client. Messages are dictionaries turned into
## bytes (never objects, so nothing on the wire can run code) and sent with send_bytes: inputs unordered-latest on
## channel 1, snapshots and the welcome reliable on channel 2. A hosted server's own player stays on its SimLink.

signal connected
signal disconnected(reason: String)

## Players over ENet at most; a pit has four slots, and the rest are told it is full.
const MAX_CLIENTS := 8
const CHANNEL_INPUT := 1
const CHANNEL_STATE := 2

var server: ArenaServer
var client: ArenaClient
var _link: SimLink
var _closing := false


## Listens on a port; peers wait for serve() to give them a server.
func host(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.peer_packet.connect(_on_packet)
	return OK


## Serves `arena_server` to every ENet peer, those connected already included; peers on `link` (a host's own player)
## stay on the link. A hosted rematch is a new server for the same peers.
func serve(arena_server: ArenaServer, link: SimLink = null) -> void:
	server = arena_server
	_link = link
	server.send = _send_from_server
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		for peer in multiplayer.get_peers():
			server.peer_joined(peer)


## Connects to a server; `arena_client` gets its messages once connected.
func join(address: String, port: int, arena_client: ArenaClient = null) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(connected.emit)
	multiplayer.connection_failed.connect(_on_lost.bind("failed"))
	multiplayer.server_disconnected.connect(_on_lost.bind("lost"))
	multiplayer.peer_packet.connect(_on_packet)
	if arena_client != null:
		join_with(arena_client)
	return OK


## Gives the connection to a (new) client.
func join_with(arena_client: ArenaClient) -> void:
	client = arena_client
	client.send = _send_to_server


func is_open() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func close() -> void:
	_closing = true
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	for s in [multiplayer.peer_connected, multiplayer.peer_disconnected, multiplayer.peer_packet, multiplayer.connected_to_server,
			multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c in s.get_connections():
			if c.callable.get_object() == self or c.callable.get_object() == null:
				s.disconnect(c.callable)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if client != null:
		client.send = Callable()
	_closing = false


func _exit_tree() -> void:
	close()


func _on_peer_connected(peer: int) -> void:
	if server != null:
		server.peer_joined(peer)


func _on_peer_disconnected(peer: int) -> void:
	if server != null:
		server.peer_left(peer)


func _on_packet(peer: int, packet: PackedByteArray) -> void:
	var message: Variant = bytes_to_var(packet)
	if server != null:
		server.receive(peer, message)
	elif client != null:
		client.receive(message)


func _on_lost(reason: String) -> void:
	if not _closing:
		disconnected.emit(reason)


func _send_from_server(peer: int, message: Dictionary) -> void:
	if _link != null and _link.has_peer(peer):
		_link.deliver(peer, message)
	elif peer in multiplayer.get_peers():
		multiplayer.send_bytes(var_to_bytes(message), peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE, CHANNEL_STATE)


func _send_to_server(message: Dictionary) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		multiplayer.send_bytes(var_to_bytes(message), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, CHANNEL_INPUT)
