extends Node2D
## One match in the pit, seen from a player's seat: the court, the HUD, pause and the result panel. Main starts it with
## setup(); on its own (a flow, a test, the editor) it plays a local match against three bots.
## The rules live in ArenaMatch and the netcode in ArenaServer and ArenaClient; this node only ticks them, reads the
## player's input and shows what the client knows. In a local or hosted match the server runs here too, and the
## player's client reaches it over a SimLink (with --lag=MS of simulated round trip); a joined match reaches a server
## over ENet through a NetSession. Everything runs in _physics_process at 30 ticks a second.

## The match ended for this player: Main records it.
signal match_over(won: bool)
signal menu_requested

## The local player's peer id on the in-process link (ENet peers have their own, larger ids).
const LOCAL_PEER := 1
## Where the court's (0, 0) is drawn: below the HUD's score line.
const COURT_ORIGIN := Vector2(40, 64)
## How long a bot run shows the finished match before it quits.
const AUTOPLAY_QUIT_TICKS := 60
const SLOT_COLORS := [Color(0.98, 0.78, 0.3), Color(0.4, 0.8, 1.0), Color(0.95, 0.45, 0.6), Color(0.55, 0.95, 0.5)]

## "local", "host" or "join".
var mode := "local"
var options: LaunchOptions
var courts: Array[Court] = []
var server: ArenaServer
var link: SimLink
var client: ArenaClient
var session: NetSession
var matches := 0
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

var _ticks := 0
var _quit_in := -1
var _reported := false
var _autopilot: Autopilot
var _shake := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()

@onready var view: Node2D = $CourtView
@onready var _camera: Camera2D = $Camera
@onready var _slot_labels: Array[Label] = [$HUD/Scores/Slot0Label, $HUD/Scores/Slot1Label, $HUD/Scores/Slot2Label, $HUD/Scores/Slot3Label]
@onready var _round_label: Label = $HUD/RoundLabel
@onready var _status_label: Label = $HUD/StatusLabel
@onready var _health_label: Label = $HUD/HealthLabel
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _result_menu: CanvasLayer = $ResultMenu
@onready var _sfx_shot: AudioStreamPlayer = $SfxShot
@onready var _sfx_hit: AudioStreamPlayer = $SfxHit
@onready var _sfx_out: AudioStreamPlayer = $SfxOut
@onready var _sfx_round: AudioStreamPlayer = $SfxRound


func setup(game_mode: String, game_options: LaunchOptions, net_session: NetSession = null) -> void:
	mode = game_mode
	options = game_options
	session = net_session


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	courts = Court.load_all()
	view.origin = COURT_ORIGIN
	view.colors = SLOT_COLORS
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.pauses_tree = mode == "local"
	_pause_menu.quit_pressed.connect(_leave)
	_result_menu.rematch_pressed.connect(rematch)
	_result_menu.menu_pressed.connect(_leave)
	_refresh_text()
	start_match()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_pause_button.text = tr("HUD_PAUSE")
	_refresh_hud()


## A new match: in a local or hosted one, a fresh server with this player's client on the link; a joined one asks the
## session's server. seed_value 0 takes the run's next seed.
func start_match(seed_value := 0) -> void:
	matches += 1
	var match_seed := seed_value if seed_value > 0 else options.match_seed(matches)
	if match_seed == 0:
		match_seed = 1 + randi() % 1000000
	_rng.seed = match_seed
	_reported = false
	_result_menu.close()
	client = ArenaClient.new(courts)
	if mode == "join":
		session.join_with(client)
	else:
		server = ArenaServer.new(courts, match_seed)
		var delay := SimLink.ticks_for_ms(options.lag_ms)
		link = SimLink.new(server, delay, maxi(delay / 4, 0), match_seed)
		if mode == "host":
			session.serve(server, link)
		link.join(client, LOCAL_PEER)
		print("[Run] match %d, seed %d" % [matches, match_seed])
	if options.autoplay:
		_autopilot = Autopilot.new(self, match_seed)
	view.client = client
	_refresh_hud()


## Plays again after a match: a new local match, or the hosted server's next one. A joined player follows its host.
func rematch() -> void:
	if state != "over":
		return
	if mode == "local":
		start_match()
	elif mode == "host":
		server.arena.restart()
		_reported = false
		_result_menu.close()


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _physics_process(delta: float) -> void:
	_ticks += 1
	_update_effects(delta)
	var input := _autopilot.player_input() if _autopilot else _read_input()
	if client.step(input.mx, input.my, input.ax, input.ay, input.fire, input.dash):
		_own_shot()
	if _autopilot:
		_autopilot.tick()
	if link:
		link.pump()
		server.tick()
		link.pump()
		link.advance()
	_take_events()
	_refresh_hud()
	view.queue_redraw()
	if _quit_in > 0:
		_quit_in -= 1
		if _quit_in == 0:
			get_tree().quit()


func _read_input() -> Dictionary:
	var input := Sim.idle()
	if get_tree().paused or not client.is_playing():
		return input
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	input.mx = Bot.axis_sign(move.x, move.y)
	input.my = Bot.axis_sign(move.y, move.x)
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var aim := stick * 100.0 if stick.length() > 0.3 else get_local_mouse_position() - COURT_ORIGIN - client.predicted.position()
	input.ax = int(aim.x)
	input.ay = int(aim.y)
	input.fire = Input.is_action_pressed("fire")
	input.dash = Input.is_action_just_pressed("dash")
	return input


## The player's own shot shows at once, from where their screen has everyone; the server's word on it comes later.
func _own_shot() -> void:
	var shot := Sim.trace(client.view.court, client.shown_fighters(), client.slot)
	_shot(client.predicted.x, client.predicted.y, shot.x, shot.y, client.slot)


func _take_events() -> void:
	for event in client.events:
		match str(event.type):
			"shot":
				if int(event.slot) != client.slot:
					_shot(event.x, event.y, event.ex, event.ey, int(event.slot))
			"hit":
				_event("player_hit")
				view.flash_fighter(int(event.slot))
				_feedback("flash")
				if int(event.slot) == client.slot:
					_flash = 0.35
					_flash_rect.color = Color(1.0, 0.25, 0.2, _flash)
				_play(_sfx_hit)
			"out":
				_event("player_out")
				view.pop(Vector2(event.x, event.y))
				_feedback("pop")
				_shake_camera(10.0)
				_play(_sfx_out)
			"round":
				_sfx_round.play()
			"over":
				_over(int(event.winner))
	client.events.clear()


func _shot(x: int, y: int, ex: int, ey: int, slot: int) -> void:
	_event("shot_fired")
	view.beam(Vector2(x, y), Vector2(ex, ey), SLOT_COLORS[slot])
	_play(_sfx_shot)


func _over(winner: int) -> void:
	if _reported:
		return
	_reported = true
	var won := winner == client.slot
	print("[Run] match over, %s" % ("won" if won else "lost"))
	match_over.emit(won)
	if options.autoplay:
		_quit_in = AUTOPLAY_QUIT_TICKS
	else:
		var scores := client.view.scores
		var second := 0
		for slot in ArenaMatch.SLOTS:
			if slot != winner:
				second = maxi(second, scores[slot])
		_result_menu.open(won, winner + 1, scores[winner], second, mode != "join")


func _leave() -> void:
	if _autopilot:
		_autopilot.stop()
	menu_requested.emit()


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
	_status_label.text = _status_text(arena, me)


func _status_text(arena: ArenaMatch, me: Fighter) -> String:
	if not client.is_playing():
		return tr("HUD_FULL") if client.full else tr("HUD_CONNECTING")
	match arena.state:
		ArenaMatch.State.WARMUP:
			return tr("HUD_GET_READY")
		ArenaMatch.State.OVER:
			return tr("HUD_OVER") % (arena.winner + 1)
	if arena.state == ArenaMatch.State.ROUND and (me == null or not me.alive):
		return tr("HUD_WAIT")
	return tr("HUD_MATCH_POINT") if arena.is_match_point() else ""


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func _shake_camera(amount: float) -> void:
	_shake = amount
	_feedback("shake")


func _play(player: AudioStreamPlayer) -> void:
	player.play()
	_feedback("sfx")


func _update_effects(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_flash_rect.color.a = _flash
	_shake = maxf(_shake - delta * 40.0, 0.0)
	_camera.offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake)) if _shake > 0.0 else Vector2.ZERO
