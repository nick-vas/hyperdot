extends Node2D
## A run down the crypt, one floor at a time: the floor drawn and the HUD. The rules live in World; this node feeds it
## the player's input (or the bot's) once per physics tick, at 60 ticks, so a bot run replays the same on every machine,
## and shows what happened. A run that ends, either way, is followed by a new one.

## Pixels a cell is drawn at.
const TILE := 22
## Where the HUD ends: the floor is drawn below it, centred.
const TOP := 112.0
## Ticks the stairs take before the next floor.
const NEXT_FLOOR_TICKS := 30
## Ticks a finished run stays on screen before the next one.
const NEXT_RUN_TICKS := 60
const WICK_HP := 5

var floors: Floors
var options: LaunchOptions
var run: Run
var world: World
## "playing", "between" (floors) or "over".
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

var _bot: Bot
var _runs := 0
var _wait := 0

@onready var _tiles: Node2D = $Tiles
@onready var _creatures: Node2D = $Creatures
@onready var _floor_label: Label = $HUD/FloorLabel
@onready var _hp_label: Label = $HUD/HpLabel
@onready var _embers_label: Label = $HUD/EmbersLabel
@onready var _enemies_label: Label = $HUD/EnemiesLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	floors = Floors.from_files()
	if options.autoplay:
		_bot = Bot.new()
	start_run()


## A new run from the first floor (or --floor); seed_value -1 takes the session's next seed.
func start_run(seed_value := -1) -> void:
	run = Run.new(seed_value if seed_value >= 0 else _next_seed(), WICK_HP)
	start_floor(options.floor_number if floors.has_floor(options.floor_number) else 1)


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
	world.enemy_snuffed.connect(_on_change)
	world.wick_hurt.connect(_on_change)
	world.stairs_opened.connect(_on_stairs_opened)
	print("[Run] floor %d, seed %d: %d rooms, %d enemies" % [number, run.floor_seed(), dungeon.rooms.size(), world.enemies.size()])
	state = "playing"
	var origin := Vector2((get_viewport_rect().size.x - dungeon.width * TILE) / 2.0, TOP)
	_tiles.position = origin
	_creatures.position = origin
	_tiles.show_dungeon(dungeon, world)
	_creatures.show_world(world)
	_refresh()


func _physics_process(delta: float) -> void:
	_creatures.advance(delta)
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
		print("[Run] died on floor %d" % run.floor_number)
		state = "over"
		_wait = NEXT_RUN_TICKS
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
	else:
		print("[Run] victory")
		state = "over"
		if options.autoplay:
			get_tree().quit()
			return
	_wait = NEXT_FLOOR_TICKS if state == "between" else NEXT_RUN_TICKS
	_refresh()


func _after_wait() -> void:
	if state == "between":
		start_floor(run.floor_number + 1)
	else:
		start_run()


func _refresh() -> void:
	if world == null or not is_node_ready():
		return
	_floor_label.text = "Floor %d" % run.floor_number
	_hp_label.text = "Wick: %d / %d" % [world.wick.hp, world.wick.max_hp]
	_embers_label.text = "Embers: %d" % (run.embers + world.embers)
	_enemies_label.text = "The stairs are open" if world.stairs_open else "Enemies left: %d" % world.enemies.size()


func _on_change(_value: Variant) -> void:
	_refresh()


func _on_stairs_opened() -> void:
	_tiles.queue_redraw()
	_refresh()
