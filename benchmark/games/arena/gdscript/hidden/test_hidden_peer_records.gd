extends GutTest
## Hidden check for the beta's fix-performance: whatever the server keeps per player goes when the player goes, so a
## server that sees hundreds of players come and go keeps no more state, and spends no more time per tick, than a new one.

var courts: Array[Court]
var server: ArenaServer
var link: SimLink


func before_each():
	courts = Court.load_all()
	server = ArenaServer.new(courts, 2)
	link = SimLink.new(server)
	var host := ArenaClient.new(courts)
	link.join(host, 1)
	for i in 10:
		_tick([host])


func _tick(clients: Array) -> void:
	for c: ArenaClient in clients:
		c.step(1, 0, 1, 0, true)
	link.pump()
	server.tick()
	link.pump()
	link.advance()


func _cycles(count: int, first_peer: int) -> void:
	for n in count:
		var peer := first_peer + n
		var guest := ArenaClient.new(courts)
		link.join(guest, peer)
		for i in 12:
			_tick([guest])
		link.leave(peer)
		_tick([])


# The sizes of every array and dictionary the server keeps, by name.
func _collections() -> Dictionary:
	var sizes := {}
	for property in server.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var value: Variant = server.get(property.name)
		if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
			sizes[property.name] = value.size()
	return sizes


func test_hidden_no_state_outlives_its_player():
	_cycles(10, 100)
	var before := _collections()
	_cycles(200, 1000)
	assert_eq(_collections(), before)
	assert_eq(server.record_count(), server.peer_count())


func test_hidden_memory_stays_flat():
	_cycles(20, 100)
	var before := Performance.get_monitor(Performance.MEMORY_STATIC)
	_cycles(300, 1000)
	var grown := Performance.get_monitor(Performance.MEMORY_STATIC) - before
	assert_lt(grown, 200000.0, "%d bytes kept after 300 players came and went" % grown)
