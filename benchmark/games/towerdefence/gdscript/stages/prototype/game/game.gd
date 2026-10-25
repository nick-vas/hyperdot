extends Node2D
## One map's battle on screen: the field, the HUD and building. The main scene of the prototype.
## The rules live in Battle; this node only feeds it ticks and input and shows what it holds. Everything runs in
## _physics_process at 60 ticks.

const SPEEDS: Array[int] = [1, 3]
const TOWER_BUTTONS := {"thorn": "HUD/Towers/ThornButton", "puff": "HUD/Towers/PuffButton", "acorn": "HUD/Towers/AcornButton"}

var catalog: Catalog
var battle: Battle
## The map's place in the campaign, from 1.
var level := 1
## "playing" or "over".
var state := "playing"
## The tower kind a click on an open cell builds.
var building := "thorn"
## The cell of the tower whose upgrade the HUD offers; (-1, -1) for none.
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

var _tower_buttons := {}

@onready var field: Node2D = $Field
@onready var _store: Sprite2D = $Store
@onready var _map_label: Label = $HUD/MapLabel
@onready var _gold_label: Label = $HUD/GoldLabel
@onready var _lives_label: Label = $HUD/LivesLabel
@onready var _wave_label: Label = $HUD/WaveLabel
@onready var _info_label: Label = $HUD/InfoLabel
@onready var _upgrade: Button = $HUD/UpgradeButton
@onready var _next_wave: Button = $HUD/NextWaveButton
@onready var _speed_button: Button = $HUD/SpeedButton


func _ready() -> void:
	if catalog == null:
		catalog = Catalog.from_files()
	for id: String in TOWER_BUTTONS:
		_tower_buttons[id] = get_node(TOWER_BUTTONS[id])
		_tower_buttons[id].pressed.connect(select_tower.bind(id))
	_upgrade.pressed.connect(upgrade_selected)
	_next_wave.pressed.connect(next_wave)
	_speed_button.pressed.connect(toggle_speed)
	start_map(1)


## A new battle on the map at this place in the campaign; seed_value -1 draws one.
func start_map(index: int, seed_value := -1) -> void:
	var row := catalog.map_at(index)
	if row.is_empty():
		push_error("There is no map %d" % index)
		return
	level = index
	var battle_seed := seed_value if seed_value >= 0 else randi() % 1000000
	print("[Run] map %d, seed %d" % [index, battle_seed])
	battle = Battle.create(catalog, str(row.id), battle_seed)
	battle.tower_placed.connect(_on_changed.unbind(1))
	battle.tower_upgraded.connect(_on_changed.unbind(1))
	battle.enemy_killed.connect(_on_changed.unbind(1))
	battle.enemy_leaked.connect(_on_changed.unbind(1))
	battle.wave_started.connect(_on_changed.unbind(1))
	battle.wave_cleared.connect(_on_changed.unbind(2))
	battle.battle_over.connect(_on_battle_over)
	state = "playing"
	selected = Vector2i(-1, -1)
	field.show_battle(battle)
	_store.position = field.cell_centre(battle.map.store)
	_refresh()


func _can_act() -> bool:
	return state == "playing" and not battle.is_over()


func select_tower(id: String) -> void:
	building = id
	selected = Vector2i(-1, -1)
	_refresh()


## Builds the chosen kind on a cell, or selects the tower already there. For tests as well as clicks.
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


func _physics_process(_delta: float) -> void:
	if state != "playing":
		return
	for i in speed:
		battle.step()
		if battle.is_over():
			break
	_wave_label.text = _wave_text()
	field.queue_redraw()


func _wave_text() -> String:
	if battle.phase == Battle.Phase.WON:
		return "Map cleared"
	if battle.phase == Battle.Phase.LOST:
		return "The store is empty"
	if battle.phase == Battle.Phase.BUILD:
		return "Wave %d / %d in %d s" % [battle.wave + 1, battle.waves.size(), ceili(battle.break_left / float(Battle.TICKS_PER_SECOND))]
	return "Wave %d / %d" % [battle.wave, battle.waves.size()]


func _on_battle_over(won: bool) -> void:
	state = "over"
	print("[Run] map %d %s" % [level, "won" if won else "lost"])
	_refresh()


func _on_changed() -> void:
	_refresh()


func _refresh() -> void:
	if battle == null or not is_node_ready():
		return
	_map_label.text = "The Meadow"
	_gold_label.text = "Sap: %d" % battle.gold
	_lives_label.text = "Seeds: %d" % battle.lives
	_wave_label.text = _wave_text()
	for id: String in _tower_buttons:
		var button: Button = _tower_buttons[id]
		button.text = "%s: %d" % [str(id).capitalize(), catalog.cost(id)]
		button.button_pressed = id == building
	var has_selection := battle.towers.has(selected)
	_upgrade.disabled = not (has_selection and battle.can_upgrade(selected))
	_upgrade.text = "Upgrade"
	if has_selection:
		var tower: Dictionary = battle.towers[selected]
		if tower.level < catalog.max_level(tower.id):
			_upgrade.text = "Upgrade: %d" % catalog.upgrade_cost(tower.id, tower.level + 1)
		_info_label.text = "%s, level %d" % [str(tower.id).capitalize(), tower.level]
	else:
		_info_label.text = "Pick a tower, then a cell."
	_next_wave.disabled = battle.phase != Battle.Phase.BUILD
	_speed_button.text = "Speed x%d" % speed
	field.selected = selected
	field.queue_redraw()
