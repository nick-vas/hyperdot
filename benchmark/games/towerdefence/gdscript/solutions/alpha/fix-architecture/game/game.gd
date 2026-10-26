extends Node2D
## One map's battle on screen: the field, the HUD, building, pause and the result panel. Main starts it with setup(); on
## its own (a flow, a test, the editor) it reads the command line and the data itself.
## The rules live in Battle; this node only feeds it ticks and input and shows what it holds. Everything runs in
## _physics_process at 60 ticks, so a bot run replays the same on every machine.

## A map ended: Main records it.
signal map_over(level: int, won: bool, lives: int, start_lives: int)
## The run is over: victory after the last map.
signal finished(victory: bool)
signal menu_requested

## How long a bot run shows a finished map before the next one.
const AUTOPLAY_NEXT_TICKS := 40
## The speeds the speed button steps through.
const SPEEDS: Array[int] = [1, 3]
const TOWER_BUTTONS := {"thorn": "HUD/Towers/ThornButton", "puff": "HUD/Towers/PuffButton", "acorn": "HUD/Towers/AcornButton"}

var catalog: Catalog
var options: LaunchOptions
var battle: Battle
## The map's place in the campaign, from 1.
var level := 1
## "playing", "over" (the result is shown) or "done".
var state := "playing"
## The tower kind a click on an open cell builds.
var building := "thorn"
## The cell of the tower whose upgrade and sale the HUD offers; (-1, -1) for none.
var selected := Vector2i(-1, -1)
## Battle ticks per physics tick.
var speed := 1
var gold: int:
	get:
		return battle.gold if battle else 0
var lives: int:
	get:
		return battle.lives if battle else 0
var wave: int:
	get:
		return battle.wave if battle else 0
var phase: String:
	get:
		return battle.phase_name() if battle else ""

var _first_level := 0
var _tower_buttons := {}
var _bot: Bot
var _runs := 0
var _ticks := 0
var _next_in := -1
var _shake := 0.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()

@onready var field: Node2D = $Field
@onready var _camera: Camera2D = $Camera
@onready var _store: Sprite2D = $Store
@onready var _map_label: Label = $HUD/MapLabel
@onready var _gold_label: Label = $HUD/GoldLabel
@onready var _lives_label: Label = $HUD/LivesLabel
@onready var _wave_label: Label = $HUD/WaveLabel
@onready var _info_label: Label = $HUD/InfoLabel
@onready var _upgrade: Button = $HUD/UpgradeButton
@onready var _sell: Button = $HUD/SellButton
@onready var _next_wave: Button = $HUD/NextWaveButton
@onready var _speed_button: Button = $HUD/SpeedButton
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _flash_rect: ColorRect = $HUD/Flash
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _result_menu: CanvasLayer = $ResultMenu
@onready var _sfx_place: AudioStreamPlayer = $SfxPlace
@onready var _sfx_kill: AudioStreamPlayer = $SfxKill
@onready var _sfx_leak: AudioStreamPlayer = $SfxLeak
@onready var _sfx_win: AudioStreamPlayer = $SfxWin


## first_level: the map to play (the command line's --map when 0).
func setup(game_catalog: Catalog, game_options: LaunchOptions, first_level := 0) -> void:
	catalog = game_catalog
	options = game_options
	_first_level = first_level


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if catalog == null:
		catalog = Catalog.from_files()
	_rng.seed = options.run_seed
	speed = options.speed
	for id: String in TOWER_BUTTONS:
		_tower_buttons[id] = get_node(TOWER_BUTTONS[id])
		_tower_buttons[id].pressed.connect(select_tower.bind(id))
	_upgrade.pressed.connect(upgrade_selected)
	_sell.pressed.connect(sell_selected)
	_next_wave.pressed.connect(next_wave)
	_speed_button.pressed.connect(toggle_speed)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_result_menu.next_pressed.connect(next_map)
	_result_menu.retry_pressed.connect(retry)
	_result_menu.menu_pressed.connect(menu_requested.emit)
	start_map(_first_level if _first_level > 0 else options.map)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


## A new battle on the map at this place in the campaign; seed_value -1 takes the run's next seed.
func start_map(index: int, seed_value := -1) -> void:
	var row := catalog.map_at(index)
	if row.is_empty():
		push_error("There is no map %d" % index)
		return
	level = index
	var battle_seed := seed_value if seed_value >= 0 else _next_seed()
	print("[Run] map %d, seed %d" % [index, battle_seed])
	battle = Battle.create(catalog, str(row.id), battle_seed)
	battle.tower_placed.connect(_on_tower_placed)
	battle.tower_upgraded.connect(_on_tower_changed)
	battle.tower_sold.connect(_on_tower_sold)
	battle.enemy_killed.connect(_on_enemy_killed)
	battle.enemy_leaked.connect(_on_enemy_leaked)
	battle.wave_started.connect(_on_wave_changed)
	battle.wave_cleared.connect(_on_wave_cleared)
	battle.battle_over.connect(_on_battle_over)
	state = "playing"
	selected = Vector2i(-1, -1)
	_next_in = -1
	_result_menu.close()
	field.show_battle(battle)
	_store.position = field.cell_centre(battle.map.store)
	_refresh()


## The run's seeds: from --seed, one per battle in order, so a bot run replays; at random without it.
func _next_seed() -> int:
	_runs += 1
	if options.run_seed > 0:
		return options.run_seed * 1009 + _runs
	return randi() % 1000000


func next_map() -> void:
	if state != "over":
		return
	if not catalog.map_at(level + 1).is_empty():
		start_map(level + 1)
	else:
		print("[Run] victory")
		_finish(true)


func retry() -> void:
	if state == "over":
		start_map(level)


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _can_act() -> bool:
	return state == "playing" and _bot == null and not battle.is_over()


func select_tower(id: String) -> void:
	building = id
	selected = Vector2i(-1, -1)
	_refresh()


## Builds the chosen kind on a cell, or selects the tower already there. For flows and tests as well as clicks.
func place_at(x: Variant, y: Variant) -> bool:
	var cell := Vector2i(int(x), int(y))
	if not _can_act():
		return false
	if battle.towers.has(cell):
		selected = cell
		_refresh()
		return false
	return battle.place(building, cell)


func upgrade_selected() -> bool:
	return _can_act() and battle.upgrade(selected)


func sell_selected() -> int:
	if not _can_act() or not battle.towers.has(selected):
		return 0
	var back := battle.sell(selected)
	selected = Vector2i(-1, -1)
	_refresh()
	return back


func next_wave() -> void:
	if _can_act():
		battle.start_wave()


func toggle_speed() -> void:
	speed = SPEEDS[(SPEEDS.find(speed) + 1) % SPEEDS.size()]
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_wave"):
		next_wave()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_speed"):
		toggle_speed()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = field.cell_at(field.get_local_mouse_position())
		if battle and battle.map.in_bounds(cell):
			place_at(cell.x, cell.y)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_ticks += 1
	_update_effects(delta)
	if state == "over":
		if _next_in > 0:
			_next_in -= 1
			if _next_in == 0:
				_bot_next()
		return
	if state != "playing":
		return
	for i in speed:
		if _bot:
			_bot.act(battle)
		battle.step()
		if battle.is_over():
			break
	_wave_label.text = _wave_text()
	field.queue_redraw()


func _wave_text() -> String:
	if battle.phase == Battle.Phase.BUILD:
		return tr("HUD_NEXT_WAVE_IN") % [battle.wave + 1, battle.waves.size(), ceili(battle.break_left / float(Battle.TICKS_PER_SECOND))]
	return tr("HUD_WAVE") % [battle.wave, battle.waves.size()]


func _on_battle_over(won: bool) -> void:
	state = "over"
	print("[Run] map %d %s" % [level, "won" if won else "lost"])
	if won:
		_sfx_win.play()
	map_over.emit(level, won, battle.lives, battle.start_lives)
	_refresh()
	if _bot:
		_next_in = AUTOPLAY_NEXT_TICKS
	else:
		var last := catalog.map_at(level + 1).is_empty()
		_result_menu.open(won, Progress.stars_for(battle.lives, battle.start_lives) if won else 0, "RESULT_FINISH" if last else "RESULT_NEXT")


## A bot run goes on: the next map after a win, the same one again after a loss, victory after the last.
func _bot_next() -> void:
	if battle.phase == Battle.Phase.WON:
		next_map()
	else:
		start_map(level)


func _finish(victory: bool) -> void:
	state = "done"
	finished.emit(victory)


func _refresh() -> void:
	if battle == null or not is_node_ready():
		return
	_map_label.text = tr(str(catalog.map_at(level).get("name", "")))
	_gold_label.text = tr("HUD_SAP") % battle.gold
	_lives_label.text = tr("HUD_SEEDS") % battle.lives
	_wave_label.text = _wave_text()
	for id: String in _tower_buttons:
		var button: Button = _tower_buttons[id]
		button.text = tr("TOWER_BUTTON") % [tr(str(catalog.towers[id].name)), catalog.cost(id)]
		button.button_pressed = id == building
	var has_selection := battle.towers.has(selected)
	_upgrade.disabled = not (has_selection and battle.can_upgrade(selected))
	_sell.disabled = not has_selection
	_upgrade.text = tr("HUD_UPGRADE")
	_sell.text = tr("HUD_SELL")
	if has_selection:
		var tower: Dictionary = battle.towers[selected]
		var price := catalog.upgrade_cost(tower.id, tower.level + 1)
		if tower.level < catalog.max_level(tower.id):
			_upgrade.text = tr("HUD_UPGRADE_FOR") % price
		_sell.text = tr("HUD_SELL_FOR") % battle.refund(selected)
		_info_label.text = tr("HUD_TOWER_INFO") % [tr(str(catalog.towers[tower.id].name)), tower.level]
	else:
		_info_label.text = tr("HUD_BUILD_HINT")
	_next_wave.text = tr("HUD_NEXT_WAVE")
	_next_wave.disabled = battle.phase != Battle.Phase.BUILD
	_speed_button.text = tr("HUD_SPEED") % speed
	_pause_button.text = tr("HUD_PAUSE")
	field.selected = selected
	field.queue_redraw()


func _on_tower_placed(cell: Vector2i) -> void:
	_event("tower_placed")
	field.pop(field.cell_centre(cell), Color(0.75, 1.0, 0.6))
	_feedback("pop")
	_play(_sfx_place)
	_refresh()


func _on_tower_changed(_cell: Vector2i) -> void:
	_refresh()


func _on_tower_sold(_cell: Vector2i, _refund: int) -> void:
	_refresh()


func _on_enemy_killed(enemy: Enemy) -> void:
	_event("enemy_killed")
	field.pop(field.to_screen(enemy.pos), Color(1.0, 0.9, 0.5))
	_feedback("pop")
	_play(_sfx_kill)
	_refresh()


func _on_enemy_leaked(_enemy: Enemy) -> void:
	_event("enemy_leaked")
	_flash_screen(Color(1.0, 0.3, 0.2, 0.35))
	_shake_camera(8.0)
	_play(_sfx_leak)
	_refresh()


func _on_wave_changed(_number: int) -> void:
	_refresh()


func _on_wave_cleared(_number: int, _bonus: int) -> void:
	_refresh()


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
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
