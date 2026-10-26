extends Node2D
## One race on Ashfall Oval: the car on the keys against three AI rivals, the chase camera and a small HUD.
## The race lives in Race; this node only counts down, feeds it the player's input once a physics tick and shows it.
## After the flag it waits a moment and starts again.

const COUNTDOWN_SECONDS := 3
const RESTART_SECONDS := 2.0
const RIVALS := 3

var tracks: Tracks
var race: Race
var track := 1
## "countdown", "racing" or "finished".
var state := "countdown"
## The lap the player is on, 1 to the track's laps.
var lap := 1

var _countdown := 0
var _restart_in := -1
var _views: Array[Node2D] = []
var _player_before := Vector2.ZERO

@onready var track_view: Node2D = $Track
@onready var camera: Camera2D = $Camera
@onready var _cars: Node2D = $Cars
@onready var _track_label: Label = $HUD/TrackLabel
@onready var _lap_label: Label = $HUD/LapLabel
@onready var _time_label: Label = $HUD/TimeLabel
@onready var _best_label: Label = $HUD/BestLabel
@onready var _countdown_label: Label = $HUD/CountdownLabel


func _ready() -> void:
	tracks = Tracks.from_files()
	start_track(track)


func start_track(id: int) -> void:
	track = id
	var circuit := tracks.track(id)
	race = Race.new(circuit, tracks.drivers_for(RIVALS, randi()), Engine.physics_ticks_per_second)
	race.lap_completed.connect(_on_lap_completed)
	race.car_finished.connect(_on_car_finished)
	track_view.show_track(circuit)
	for view in _views:
		_cars.remove_child(view)
		view.queue_free()
	_views.clear()
	var colours := [Color("#f2c14e"), Color("#e4572e"), Color("#4c9f70"), Color("#7b6ccf")]
	for i in race.cars.size():
		var view := CarView.new()
		view.name = "Car%d" % i
		view.color = colours[i % colours.size()]
		_cars.add_child(view)
		_views.append(view)
	_sync_views()
	state = "countdown"
	_countdown = COUNTDOWN_SECONDS * Engine.physics_ticks_per_second
	_restart_in = -1
	lap = 1
	_player_before = race.cars[0].position
	camera.reset_to(race.cars[0].position)
	_update_hud()


func _physics_process(_delta: float) -> void:
	if state == "countdown":
		_countdown -= 1
		if _countdown <= 0:
			state = "racing"
		_update_hud()
		return
	_player_before = race.cars[0].position
	var throttle := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	race.step(Vector2(throttle, Input.get_axis("steer_left", "steer_right")))
	_sync_views()
	if _restart_in > 0:
		_restart_in -= 1
		if _restart_in == 0:
			start_track(track)
			return
	_update_hud()


func _process(delta: float) -> void:
	# Between two ticks, where the car is drawn: physics interpolation's fraction of the way from the last tick.
	var drawn := _player_before.lerp(race.cars[0].position, Engine.get_physics_interpolation_fraction())
	camera.follow(drawn, race.cars[0].velocity(), delta)


func _sync_views() -> void:
	for i in _views.size():
		_views[i].position = race.cars[i].position
		_views[i].rotation = race.cars[i].heading


func _on_lap_completed(car: int, laps_done: int, ticks: int) -> void:
	if car == 0:
		print("[Run] track %d lap %d %.3f" % [track, laps_done, ticks / float(race.rate)])
		lap = mini(laps_done + 1, race.track.laps)


func _on_car_finished(car: int, _place: int) -> void:
	if car == 0:
		state = "finished"
		race.drivers[0] = AiDriver.new(0.6)
		_restart_in = int(RESTART_SECONDS * race.rate)


func _update_hud() -> void:
	_track_label.text = "Ashfall Oval"
	_lap_label.text = "Lap %d/%d" % [lap, race.track.laps]
	var tracker := race.trackers[0]
	var running := 0 if state == "countdown" else race.tick - tracker.lap_start_tick
	_time_label.text = "Lap %s" % Race.format_ms(roundi(running * 1000.0 / race.rate))
	_best_label.text = "Best %s" % (Race.format_ms(roundi(tracker.best_lap * 1000.0 / race.rate)) if tracker.best_lap >= 0 else "-")
	if state == "countdown":
		_countdown_label.text = str(ceili(_countdown / float(Engine.physics_ticks_per_second)))
	elif state == "finished":
		_countdown_label.text = "Finished"
	else:
		_countdown_label.text = "GO!" if race.tick < Engine.physics_ticks_per_second else ""
