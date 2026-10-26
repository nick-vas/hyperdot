extends Node2D
## One local match in the pit against three bots: the court and the scores. The rules live in ArenaMatch and the
## netcode in ArenaServer and ArenaClient; this node runs the server, reaches it with the player's client over a
## SimLink (with --lag=MS of simulated round trip), reads the player's input and shows what the client knows.
## Everything runs in _physics_process at 30 ticks a second.

## The local player's peer id on the in-process link.
const LOCAL_PEER := 1
## Where the court's (0, 0) is drawn: below the HUD's score line.
const COURT_ORIGIN := Vector2(40, 64)
const SLOT_COLORS := [Color(0.98, 0.78, 0.3), Color(0.4, 0.8, 1.0), Color(0.95, 0.45, 0.6), Color(0.55, 0.95, 0.5)]

var options: LaunchOptions
var courts: Array[Court] = []
var server: ArenaServer
var link: SimLink
var client: ArenaClient
## "warmup", "round", "intermission" or "over", as this player's client knows it.
var state: String:
	get:
		return client.view.state_name() if client else ""
var round_number: int:
	get:
		return client.view.round_number if client else 0
var my_slot: int:
	get:
		return client.slot if client else -1

@onready var view: Node2D = $CourtView
@onready var _slot_labels: Array[Label] = [$HUD/Scores/Slot0Label, $HUD/Scores/Slot1Label, $HUD/Scores/Slot2Label, $HUD/Scores/Slot3Label]
@onready var _round_label: Label = $HUD/RoundLabel
@onready var _status_label: Label = $HUD/StatusLabel
@onready var _health_label: Label = $HUD/HealthLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	courts = Court.load_all()
	view.origin = COURT_ORIGIN
	view.colors = SLOT_COLORS
	start_match()


## A new local match: a fresh server with this player's client on the link.
func start_match() -> void:
	var match_seed := options.match_seed(1)
	if match_seed == 0:
		match_seed = 1 + randi() % 1000000
	client = ArenaClient.new(courts)
	server = ArenaServer.new(courts, match_seed)
	var delay := SimLink.ticks_for_ms(options.lag_ms)
	link = SimLink.new(server, delay, maxi(delay / 4, 0), match_seed)
	link.join(client, LOCAL_PEER)
	print("[Run] match, seed %d" % match_seed)
	view.client = client
	_refresh_hud()


func _physics_process(_delta: float) -> void:
	var input := _read_input()
	if client.step(input.mx, input.my, input.ax, input.ay, input.fire):
		_own_shot()
	link.pump()
	server.tick()
	link.pump()
	link.advance()
	_take_events()
	_refresh_hud()
	view.queue_redraw()


func _read_input() -> Dictionary:
	var input := Sim.idle()
	if not client.is_playing():
		return input
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input.mx = Bot.axis_sign(move.x, move.y)
	input.my = Bot.axis_sign(move.y, move.x)
	var aim := get_local_mouse_position() - COURT_ORIGIN - client.predicted.position()
	input.ax = int(aim.x)
	input.ay = int(aim.y)
	input.fire = Input.is_action_pressed("fire")
	return input


## The player's own shot shows at once, from where their screen has everyone; the server's word on it comes later.
func _own_shot() -> void:
	var shot := Sim.trace(client.view.court, client.shown_fighters(), client.slot)
	view.beam(client.predicted.position(), Vector2(shot.x, shot.y), SLOT_COLORS[client.slot])


func _take_events() -> void:
	for event in client.events:
		match str(event.type):
			"shot":
				if int(event.slot) != client.slot:
					view.beam(Vector2(event.x, event.y), Vector2(event.ex, event.ey), SLOT_COLORS[int(event.slot)])
			"hit":
				view.flash_fighter(int(event.slot))
			"out":
				view.pop(Vector2(event.x, event.y))
	client.events.clear()


func _refresh_hud() -> void:
	if client == null or not is_node_ready():
		return
	var arena := client.view
	for slot in ArenaMatch.SLOTS:
		var key := "HUD_SLOT_YOU" if slot == client.slot else ("HUD_SLOT_BOT" if arena.is_bot(slot) else "HUD_SLOT")
		_slot_labels[slot].text = tr(key) % [slot + 1, arena.scores[slot]]
		_slot_labels[slot].modulate = SLOT_COLORS[slot]
	_round_label.text = tr("HUD_ROUND") % arena.round_number
	var me: Fighter = client.predicted
	_health_label.text = tr("HUD_HEALTH") % (me.hp if me != null and me.alive else 0)
	match arena.state:
		ArenaMatch.State.WARMUP:
			_status_label.text = tr("HUD_GET_READY")
		ArenaMatch.State.OVER:
			_status_label.text = tr("HUD_OVER") % (arena.winner + 1)
		_:
			_status_label.text = tr("HUD_WAIT") if me == null or not me.alive else ""
