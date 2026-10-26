extends Node
## The game without a screen: a dedicated server (--server, or soak's --soak-role=server) that plays match after match
## with bots in the empty slots, or a soak client (--soak-role=client) whose bot plays through ENet and leaves and
## rejoins every few seconds, as players do. Both take part in `hyperdot.ps1 soak` through its printed lines: [soak]
## ready, [soak] metric <name> <value> every few seconds, and [soak] fail <reason> when the game finds something wrong.

## Seconds between metric lines.
const METRIC_SECONDS := 5.0
## A soak client stays this long plus its id in seconds, then leaves, and is back after REJOIN_TICKS.
const STAY_SECONDS := 4
const REJOIN_TICKS := 30

var options: LaunchOptions
var courts: Array[Court] = []
var server: ArenaServer
var client: ArenaClient
var session: NetSession

var _bot: Bot
var _ticks := 0
var _connected_ticks := 0
var _away := -1
var _ready_said := false
var _joins := 0


func setup(headless_options: LaunchOptions) -> void:
	options = headless_options


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	# Headless Godot would run as fast as it can; a server needs no more frames than ticks.
	Engine.max_fps = 60
	courts = Court.load_all()
	session = NetSession.new()
	session.name = "Net"
	add_child(session)
	if options.server:
		_serve()
	else:
		_bot = Bot.new(0, maxi(options.soak_id, 1) * 104729)
		session.connected.connect(_on_connected)
		session.disconnected.connect(_on_disconnected)
		_join()


func _serve() -> void:
	server = ArenaServer.new(courts, options.run_seed if options.run_seed > 0 else 1)
	server.loop_matches = true
	var err := session.host(options.port)
	if err != OK:
		print("[soak] fail the server could not listen on %d: %s" % [options.port, error_string(err)])
		return
	session.serve(server)
	print("[Server] listening on %d" % options.port)
	print("[soak] ready")


func _join() -> void:
	client = ArenaClient.new(courts)
	var err := session.join("127.0.0.1", options.port, client)
	if err != OK:
		print("[soak] fail could not connect: %s" % error_string(err))


func _on_connected() -> void:
	_joins += 1
	_connected_ticks = 0
	if not _ready_said:
		_ready_said = true
		print("[soak] ready")


func _on_disconnected(reason: String) -> void:
	print("[soak] fail the connection to the server was %s" % reason)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if server != null:
		server.tick()
	elif _away > 0:
		_away -= 1
		if _away == 0:
			_join()
	elif client != null and client.is_playing():
		_bot.slot = client.slot
		var input := _bot.decide(client.view, client.predicted)
		client.step(input.mx, input.my, input.ax, input.ay, input.fire, input.dash)
		client.events.clear()
		_connected_ticks += 1
		if _connected_ticks >= (STAY_SECONDS + options.soak_id) * Sim.TICK_RATE:
			session.close()
			client = null
			_away = REJOIN_TICKS
	if _ticks % int(METRIC_SECONDS * Sim.TICK_RATE) == 0:
		_metrics()


func _metrics() -> void:
	if server != null:
		print("[soak] metric players %d" % server.peer_count())
		print("[soak] metric peer_records %d" % server.record_count())
		print("[soak] metric matches %d" % server.arena.matches)
		print("[soak] metric refused_claims %d" % server.arena.refused_claims)
		# Whatever the server keeps per peer must go when the peer goes: more records than peers is a leak.
		if server.record_count() > server.peer_count():
			print("[soak] fail the server keeps %d peer records for %d players" % [server.record_count(), server.peer_count()])
	else:
		print("[soak] metric joins %d" % _joins)
		if client != null:
			print("[soak] metric snapshots %d" % client.snapshots)
			print("[soak] metric corrections %d" % client.corrections)
