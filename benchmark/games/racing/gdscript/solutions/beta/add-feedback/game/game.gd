extends Node2D
## One race: the track, the cars, the ghost of the best lap, the chase camera, the HUD, pause and the result panel.
## Main starts it with setup(); on its own (a flow, a test, the editor) it reads the command line and the data itself.
## The race lives in Race; this node only counts down, feeds it the player's input once a physics tick and shows it.

## The player took the flag: Main records the place and the best lap.
signal race_finished(track_id: int, place: int, best_ms: int, ghost: Ghost)
## The run is over: victory after the last track.
signal finished(victory: bool)
signal menu_requested

const COUNTDOWN_SECONDS := 3
## A place this good or better opens the next track.
const TOP_PLACES := 2
## How long the finish shows before the result panel (and, in a bot run, the next race).
const RESULT_SECONDS := 1.0

var tracks: Tracks
var options: LaunchOptions
var save := {}
var race: Race
var track := 1
## "countdown", "racing" or "finished".
var state := "countdown"
## The player's place, 1 for the lead.
var place := 0
## The lap the player is on, 1 to the track's laps.
var lap := 1

var _bot := false
var _races := 0
var _race_seed := 0
var _ticks := 0
var _countdown := 0
var _result_in := -1
var _views: Array[Node2D] = []
## Where the player's car was before the last tick, for the camera between ticks.
var _player_before := Vector2.ZERO
var _ghost: Ghost
var _ghost_car: Car
var _ghost_tick := 0
var _flash := 0.0
var _pop_lap := 0.0
var _pop_place := 0.0

@onready var track_view: Node2D = $Track
@onready var camera: Camera2D = $Camera
@onready var _cars: Node2D = $Cars
@onready var _ghost_view: CarView = $Ghost
@onready var _track_label: Label = $HUD/TrackLabel
@onready var _lap_label: Label = $HUD/LapLabel
@onready var _place_label: Label = $HUD/PositionLabel
@onready var _time_label: Label = $HUD/TimeLabel
@onready var _best_label: Label = $HUD/BestLabel
@onready var _countdown_label: Label = $HUD/CountdownLabel
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _result_menu: CanvasLayer = $ResultMenu
@onready var _sfx_go: AudioStreamPlayer = $SfxGo
@onready var _sfx_lap: AudioStreamPlayer = $SfxLap
@onready var _sfx_pass: AudioStreamPlayer = $SfxPass


func setup(game_tracks: Tracks, game_options: LaunchOptions, game_save := {}) -> void:
	tracks = game_tracks
	options = game_options
	save = game_save


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if tracks == null:
		tracks = Tracks.from_files()
	_bot = options.autoplay
	_ghost_view.ghost = true
	_ghost_view.color = Color(1, 1, 1, 0.6)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.restart_pressed.connect(restart)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_result_menu.next_pressed.connect(next_track)
	_result_menu.retry_pressed.connect(restart)
	_result_menu.menu_pressed.connect(menu_requested.emit)
	_refresh_text()
	start_track(options.track)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_pause_button.text = tr("HUD_PAUSE")
	_update_hud()


## A new race on a track; seed_value -1 takes the run's next seed.
func start_track(id: int, seed_value := -1) -> void:
	if not tracks.has_track(id):
		push_error("There is no track %d" % id)
		return
	track = id
	var race_seed := seed_value if seed_value >= 0 else _next_seed()
	print("[Run] track %d, seed %d" % [id, race_seed])
	var circuit := tracks.track(id)
	race = Race.new(circuit, tracks.drivers_for(options.rivals, race_seed, _bot), Engine.physics_ticks_per_second)
	_race_seed = race_seed
	race.lap_completed.connect(_on_lap_completed)
	race.car_finished.connect(_on_car_finished)
	track_view.show_track(circuit)
	_make_views()
	_ghost = Ghost.from_dict(save.get("ghosts", {}).get(str(id), null))
	_restart_ghost()
	state = "countdown"
	_countdown = COUNTDOWN_SECONDS * Engine.physics_ticks_per_second
	_result_in = -1
	lap = 1
	place = race.position_of(0)
	_result_menu.close()
	_player_before = race.cars[0].position
	camera.reset_to(race.cars[0].position)
	_update_hud()


## The run's seeds: from --seed, one per race in order, so a bot run replays; at random without it.
func _next_seed() -> int:
	_races += 1
	if options.run_seed > 0:
		return options.run_seed * 1009 + _races
	return randi() % 1000000


func restart() -> void:
	start_track(track)


func next_track() -> void:
	if tracks.has_track(track + 1):
		start_track(track + 1)
	else:
		print("[Run] victory")
		finished.emit(true)
		if _bot and finished.get_connections().is_empty():
			get_tree().quit()


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _make_views() -> void:
	for view in _views:
		_cars.remove_child(view)
		view.queue_free()
	_views.clear()
	var colours := ["#f2c14e"]
	for k in tracks.grid_order(race.cars.size() - 1, _race_seed):
		colours.append(str(tracks.rivals[k].get("color", "#cccccc")))
	for i in race.cars.size():
		var view := CarView.new()
		view.name = "Car%d" % i
		view.color = Color(colours[i]) if i < colours.size() else Color.GRAY
		_cars.add_child(view)
		_views.append(view)
	_sync_views()
	for view in _views:
		view.reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	_update_effects(1.0 / Engine.physics_ticks_per_second)
	if race == null:
		return
	if state == "countdown":
		_countdown -= 1
		if _countdown <= 0:
			state = "racing"
			_event("race_start")
			_flash_screen(Color(1, 1, 1, 0.35))
			_play(_sfx_go)
		_update_hud()
		return
	_player_before = race.cars[0].position
	race.step(_player_input())
	_sync_views()
	_step_ghost()
	var now := race.position_of(0)
	if state == "racing" and now < place:
		_gained_place()
	place = now
	if _result_in > 0:
		_result_in -= 1
		if _result_in == 0:
			_show_result()
	_update_hud()


func _player_input() -> Vector2:
	if _bot or race.is_finished(0):
		return Vector2.ZERO
	var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	return Vector2(throttle, Input.get_axis("steer_left", "steer_right"))


func _process(delta: float) -> void:
	if race == null:
		return
	# Between two ticks, where the car is drawn: physics interpolation's fraction of the way from the last tick.
	var drawn := _player_before.lerp(race.cars[0].position, Engine.get_physics_interpolation_fraction())
	camera.follow(drawn, race.cars[0].velocity(), delta)


func _sync_views() -> void:
	for i in _views.size():
		var car := race.cars[i]
		_views[i].position = car.position
		_views[i].rotation = car.heading


func _restart_ghost() -> void:
	_ghost_tick = 0
	_ghost_car = null
	if _ghost != null and _ghost.rate == Engine.physics_ticks_per_second and _ghost.ticks() > 0:
		_ghost_car = _ghost.start_car()
		_ghost_car.index = race.track.nearest(_ghost_car.position)
	_ghost_view.visible = _ghost_car != null
	_place_ghost()


func _step_ghost() -> void:
	if _ghost_car == null:
		return
	if _ghost_tick >= _ghost.ticks():
		_ghost_view.visible = false
		return
	_ghost.drive(_ghost_car, _ghost_tick, race.track)
	_ghost_tick += 1
	_place_ghost()


func _place_ghost() -> void:
	if _ghost_car != null:
		_ghost_view.position = _ghost_car.position
		_ghost_view.rotation = _ghost_car.heading
		if _ghost_tick == 0:
			_ghost_view.reset_physics_interpolation()


func _on_lap_completed(car: int, laps_done: int, ticks: int) -> void:
	if car != 0:
		return
	print("[Run] track %d lap %d %.3f" % [track, laps_done, ticks / float(race.rate)])
	_event("lap_completed")
	_pop_lap = 0.4
	_feedback("pop")
	_play(_sfx_lap)
	lap = mini(laps_done + 1, race.track.laps)
	# The ghost to chase is the best lap there is: this race's, once it beats the saved one.
	if _ghost == null or race.best_ghost.ticks() < _ghost.ticks() or _ghost.rate != race.rate:
		_ghost = race.best_ghost
	_restart_ghost()


func _on_car_finished(car: int, finished_place: int) -> void:
	if car != 0:
		return
	state = "finished"
	place = finished_place
	var total := 0
	for t in race.trackers[0].lap_times:
		total += t
	print("[Run] track %d finished P%d %.3f" % [track, finished_place, total / float(race.rate)])
	# The player's car drives on by itself, slowly, behind the result.
	race.drivers[0] = AiDriver.new(0.6)
	_result_in = int(RESULT_SECONDS * race.rate)
	var best_ms := roundi(race.trackers[0].best_lap * 1000.0 / race.rate)
	race_finished.emit(track, finished_place, best_ms, race.best_ghost)


func _show_result() -> void:
	var opens_next := place <= TOP_PLACES
	if _bot:
		if opens_next:
			next_track()
		else:
			start_track(track)
		return
	var best_ms := roundi(race.trackers[0].best_lap * 1000.0 / race.rate)
	_result_menu.open(place, race.cars.size(), best_ms, opens_next)


func _gained_place() -> void:
	_event("position_gained")
	_pop_place = 0.4
	_feedback("pop")
	_play(_sfx_pass)


func _update_hud() -> void:
	if race == null:
		return
	_track_label.text = tr(race.track.name_key)
	_lap_label.text = tr("HUD_LAP") % [lap, race.track.laps]
	_place_label.text = tr("HUD_POSITION") % [place, race.cars.size()]
	var tracker := race.trackers[0]
	var running := 0 if state == "countdown" else race.tick - tracker.lap_start_tick
	_time_label.text = tr("HUD_TIME") % Race.format_ms(roundi(running * 1000.0 / race.rate))
	var best := int(save.get("best", {}).get(str(track), -1))
	if tracker.best_lap >= 0:
		var this_race := roundi(tracker.best_lap * 1000.0 / race.rate)
		best = this_race if best < 0 else mini(best, this_race)
	_best_label.text = tr("HUD_BEST") % (Race.format_ms(best) if best >= 0 else "-")
	if state == "countdown":
		_countdown_label.visible = true
		_countdown_label.text = str(ceili(_countdown / float(Engine.physics_ticks_per_second)))
	else:
		_countdown_label.visible = race.tick < Engine.physics_ticks_per_second
		_countdown_label.text = tr("HUD_GO")



# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func _flash_screen(color: Color) -> void:
	_flash = color.a
	_flash_rect.color = color
	_feedback("flash")


func _play(sound: AudioStreamPlayer) -> void:
	sound.play()
	_feedback("sfx")


func _update_effects(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_flash_rect.color.a = _flash
	_pop_lap = maxf(_pop_lap - delta * 2.0, 0.0)
	_lap_label.scale = Vector2.ONE * (1.0 + _pop_lap)
	_pop_place = maxf(_pop_place - delta * 2.0, 0.0)
	_place_label.scale = Vector2.ONE * (1.0 + _pop_place)
