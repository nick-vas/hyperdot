extends Node2D
## A run down the crypt, one floor at a time: the floor drawn, the HUD, pause and the panel at the end of a run. Main
## starts it with setup(); on its own (a flow, a test, the editor) it reads the command line and the data itself.
## The rules live in World; this node feeds it the player's input (or the bot's) once per physics tick, at 60 ticks,
## so a bot run replays the same on every machine, and shows what happened.

## The run ended: Main banks its embers.
signal run_over(won: bool, floor_number: int, embers: int)
## A floor began: Main keeps the run in the save, for Continue.
signal checkpoint(data: Dictionary)
## A bot run is over: victory.
signal finished
signal menu_requested

## Pixels a cell is drawn at.
const TILE := 22
## Where the HUD ends: the floor is drawn below it, centred.
const TOP := 112.0
## Ticks the stairs take before the next floor.
const NEXT_FLOOR_TICKS := 30
## How long a bot run shows a death before it descends again.
const AUTOPLAY_NEXT_TICKS := 60

var floors: Floors
var options: LaunchOptions
var run: Run
var world: World
## "playing", "between" (floors), "over" (the panel is shown) or "done".
var state := "playing"
var floor_number: int:
	get:
		return run.floor_number if run else 0
var hp: int:
	get:
		return world.wick.hp if world else 0
var enemies_left: int:
	get:
		return world.enemies.size() if world else 0
var wick_cell: Vector2i:
	get:
		return world.wick.cell if world else Vector2i.ZERO

var _max_hp := Meta.BASE_HP
var _saved := {}
var _bot: Bot
var _runs := 0
var _ticks := 0
var _wait := 0
var _shake := 0.0
var _flash := 0.0
## Cosmetic only (the camera's shake): never the world's.
var _rng := RandomNumberGenerator.new()

@onready var _camera: Camera2D = $Camera
@onready var _tiles: Node2D = $Tiles
@onready var _creatures: Node2D = $Creatures
@onready var _floor_label: Label = $HUD/FloorLabel
@onready var _hp_label: Label = $HUD/HpLabel
@onready var _embers_label: Label = $HUD/EmbersLabel
@onready var _enemies_label: Label = $HUD/EnemiesLabel
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _run_over_menu: CanvasLayer = $RunOverMenu
@onready var _sfx_hit: AudioStreamPlayer = $SfxHit
@onready var _sfx_hurt: AudioStreamPlayer = $SfxHurt
@onready var _sfx_snuff: AudioStreamPlayer = $SfxSnuff
@onready var _sfx_stairs: AudioStreamPlayer = $SfxStairs


## max_hp: the wick's hp with the vigor bought; saved: a run from the save to carry on instead of a new one.
func setup(game_floors: Floors, game_options: LaunchOptions, max_hp := Meta.BASE_HP, saved := {}) -> void:
	floors = game_floors
	options = game_options
	_max_hp = max_hp
	_saved = saved


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if floors == null:
		floors = Floors.from_files()
	_rng.seed = options.run_seed
	if options.autoplay:
		_bot = Bot.new()
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_run_over_menu.again_pressed.connect(start_run)
	_run_over_menu.menu_pressed.connect(menu_requested.emit)
	_refresh_text()
	if not _saved.is_empty():
		resume(_saved)
	else:
		start_run()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_pause_button.text = tr("HUD_PAUSE")
	_refresh()


## A new run from the first floor (or --floor); seed_value -1 takes the session's next seed.
func start_run(seed_value := -1) -> void:
	run = Run.new(seed_value if seed_value >= 0 else _next_seed(), _max_hp)
	start_floor(options.floor_number if floors.has_floor(options.floor_number) else 1)


## Carries on a run kept in the save (Run.to_dict): its floor again from the start, with the hp and embers it had.
func resume(data: Dictionary) -> void:
	run = Run.from_dict(data)
	start_floor(run.floor_number if floors.has_floor(run.floor_number) else 1)


## The run's seeds: from --seed, the seed itself and then one more for each run after; at random without it.
func _next_seed() -> int:
	_runs += 1
	if options.run_seed > 0:
		return options.run_seed + _runs - 1
	return randi() % 1000000 + 1


func start_floor(number: int) -> void:
	run.floor_number = number
	var dungeon := Dungeon.generate(run.floor_seed(), floors.spec(number))
	world = World.create(dungeon, floors.kinds, run.floor_seed(), run.hp, run.max_hp)
	if options.swarm > 0:
		world.add_swarm(options.swarm, floors.kind("bat"))
	world.enemy_hit.connect(_on_enemy_hit)
	world.enemy_snuffed.connect(_on_enemy_snuffed)
	world.wick_hurt.connect(_on_wick_hurt)
	world.stairs_opened.connect(_on_stairs_opened)
	print("[Run] floor %d, seed %d: %d rooms, %d enemies" % [number, run.floor_seed(), dungeon.rooms.size(), world.enemies.size()])
	state = "playing"
	_run_over_menu.close()
	var origin := Vector2((get_viewport_rect().size.x - dungeon.width * TILE) / 2.0, TOP)
	_tiles.position = origin
	_creatures.position = origin
	_tiles.show_dungeon(dungeon, world)
	_creatures.show_world(world)
	if _bot == null:
		checkpoint.emit(run.to_dict())
	_refresh()


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _physics_process(delta: float) -> void:
	_ticks += 1
	_update_effects(delta)
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_after_wait()
		return
	if state != "playing" or world == null:
		return
	var choice := _bot.choose(world) if _bot else _read_input()
	world.step(choice.move, choice.attack)
	if world.wick.hp <= 0:
		_end_run(false)
	elif world.done:
		_floor_cleared()


## The player's input this tick: one direction held (up first) and whether attack is held.
func _read_input() -> Dictionary:
	var move := Vector2i.ZERO
	if Input.is_action_pressed("move_up"):
		move = Vector2i.UP
	elif Input.is_action_pressed("move_down"):
		move = Vector2i.DOWN
	elif Input.is_action_pressed("move_left"):
		move = Vector2i.LEFT
	elif Input.is_action_pressed("move_right"):
		move = Vector2i.RIGHT
	return {"move": move, "attack": Input.is_action_pressed("attack")}


## The wick took the stairs: its embers join the run, the stairs' candle relights one hp, and the next floor follows.
func _floor_cleared() -> void:
	run.embers += world.embers
	run.hp = mini(world.wick.hp + 1, run.max_hp)
	print("[Run] floor %d cleared" % run.floor_number)
	if floors.has_floor(run.floor_number + 1):
		state = "between"
		_wait = NEXT_FLOOR_TICKS
	else:
		print("[Run] victory")
		_end_run(true)


func _end_run(won: bool) -> void:
	if not won:
		run.embers += world.embers
		print("[Run] died on floor %d" % run.floor_number)
	state = "over"
	run_over.emit(won, run.floor_number, run.embers)
	if _bot:
		if won:
			_finish()
		else:
			_wait = AUTOPLAY_NEXT_TICKS
	else:
		_run_over_menu.open(won, run.floor_number, run.embers if won else run.embers / 2)
	_refresh()


func _after_wait() -> void:
	if state == "between":
		start_floor(run.floor_number + 1)
	elif state == "over" and _bot:
		start_run()


func _finish() -> void:
	state = "done"
	finished.emit()
	# On its own (a flow, or the game scene run alone) nobody listens; a bot run then ends here.
	if options.autoplay and finished.get_connections().is_empty():
		get_tree().quit()


func _refresh() -> void:
	if world == null or not is_node_ready():
		return
	_floor_label.text = tr("HUD_FLOOR") % [run.floor_number, tr(str(floors.spec(run.floor_number).get("name", "")))]
	_hp_label.text = tr("HUD_HP") % [world.wick.hp, world.wick.max_hp]
	_embers_label.text = tr("HUD_EMBERS") % (run.embers + world.embers)
	_enemies_label.text = tr("HUD_STAIRS_OPEN") if world.stairs_open else tr("HUD_ENEMIES") % world.enemies.size()


func _on_enemy_hit(_enemy: Actor) -> void:
	_event("enemy_hit")
	_play(_sfx_hit)


func _on_enemy_snuffed(enemy: Actor) -> void:
	_event("enemy_snuffed")
	_creatures.pop(enemy.cell)
	_feedback("pop")
	_play(_sfx_snuff)
	_refresh()


func _on_wick_hurt(_amount: int) -> void:
	_event("wick_hurt")
	_flash_screen(Color(1.0, 0.25, 0.15, 0.4))
	_shake_camera(7.0)
	_play(_sfx_hurt)
	_refresh()


func _on_stairs_opened() -> void:
	_sfx_stairs.play()
	_tiles.queue_redraw()
	_refresh()


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together. The
# stairs' sound is not logged as feedback, so it cannot stand in for another event's.
func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func _flash_screen(color: Color) -> void:
	_flash = color.a
	_flash_rect.color = color
	_feedback("flash")


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
	_creatures.advance(delta)
