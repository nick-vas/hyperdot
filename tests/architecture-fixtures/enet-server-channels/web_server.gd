extends Node
## WebSocket's create_server(port, bind_address, tls_options) has the same shape as ENet's, and is not the ENet bug.

func host_web(port: int, tls: TLSOptions) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	peer.create_server(port, "*", tls)
	var plain := WebSocketMultiplayerPeer.new()
	plain.create_server(port, "127.0.0.1", TLSOptions.server(null, null))
	var other := WebSocketMultiplayerPeer.new()
	other.create_server(port, "*", null)
