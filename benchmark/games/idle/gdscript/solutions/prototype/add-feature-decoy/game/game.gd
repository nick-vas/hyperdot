extends Control
## The hive: the glow counter, Gather and the producers. The rules live in Economy; this node ticks them in
## _physics_process (60 ticks a second) and shows them.

## The buy amounts the mode button steps through; 0 is as many as the glow pays for.
const MODES := [1, 10, 0]
const MODE_KEYS := {1: "MODE_ONE", 10: "MODE_TEN", 0: "MODE_MAX"}

var catalog: Catalog
var economy: Economy
## The amount the producer rows buy: 1, 10 or 0 (as many as the glow pays for).
var buy_mode := 1

var _rows := {}

@onready var _glow: Label = $Safe/Column/Top/GlowLabel
@onready var _rate: Label = $Safe/Column/Top/RateLabel
@onready var _gather: Button = $Safe/Column/GatherButton
@onready var _page_title: Label = $Safe/Column/Header/PageTitle
@onready var _mode: Button = $Safe/Column/Header/BuyModeButton
@onready var _producer_list: VBoxContainer = $Safe/Column/ProducerPage/List
@onready var _sky: Control = $Sky


func _ready() -> void:
	catalog = Catalog.from_files()
	economy = Economy.new(catalog)
	_gather.pressed.connect(gather)
	_mode.pressed.connect(next_mode)
	for producer: Dictionary in catalog.producers:
		var row := ProducerRow.new()
		row.setup(producer)
		row.buy_pressed.connect(buy)
		_producer_list.add_child(row)
		_rows[row.id] = row
	economy.bought.connect(func(_id: String, _amount: int) -> void: _refresh())
	_refresh()


func _physics_process(delta: float) -> void:
	economy.tick(delta)
	_refresh()


## Gather: a press of the big button.
func gather() -> void:
	economy.tap()
	_refresh()


## Buys the buy mode's amount of a producer.
func buy(id: String) -> bool:
	if buy_mode == 0:
		return economy.buy_max(id) > 0
	return economy.buy(id, buy_mode)


func next_mode() -> void:
	buy_mode = MODES[(MODES.find(buy_mode) + 1) % MODES.size()]
	_refresh()


## Glow for tests and flows: as if it had been earned.
func add_glow(amount: float) -> void:
	economy.earn(amount)
	_refresh()


func _refresh() -> void:
	if economy == null or not is_node_ready():
		return
	ProducerRow._set_text(_glow, tr("HUD_GLOW") % Numbers.format(economy.glow))
	ProducerRow._set_text(_rate, tr("HUD_RATE") % Numbers.format_rate(economy.rate()))
	ProducerRow._set_text(_gather, tr("GATHER") % Numbers.format(economy.tap_value()))
	ProducerRow._set_text(_page_title, tr("PAGE_PRODUCERS"))
	ProducerRow._set_text(_mode, tr(MODE_KEYS[buy_mode]))
	for row: ProducerRow in _rows.values():
		row.refresh(economy, buy_mode)
	_sky.set("glow", economy.glow)
