extends Control
## The hive: the glow counter, Gather, the producer and upgrade pages, the dawn, and the panels for time away and for
## the dawn. Main gives it the saved economy with setup(); on its own (a flow, a test, the editor) it starts a new one.
## The rules live in Economy; this node ticks them in _physics_process (60 ticks a second, times --speed), shows them,
## gives each event its feedback and, with --autoplay, lets the bot play.

## A dawn happened: Main saves at once, since the run before it is gone.
signal dawned(embers: float)
signal settings_requested
## The bot reached its goal (--autoplay).
signal finished

## The bot's goal: this much glow earned over all runs.
const GOAL_GLOW := 1e9
## The buy amounts the mode button steps through; 0 is as many as the glow pays for.
const MODES := [1, 10, 0]
const MODE_KEYS := {1: "MODE_ONE", 10: "MODE_TEN", 0: "MODE_MAX"}
const POP_SECONDS := 0.15
const FLASH_SECONDS := 0.35
const SHAKE_SECONDS := 0.35

var catalog: Catalog
var options: LaunchOptions
var economy: Economy
## The amount the producer rows buy: 1, 10 or 0 (as many as the glow pays for).
var buy_mode := 1
## The page shown: "producers" or "upgrades".
var page := "producers"
var goal_reached := false

var _saved := {}
var _ticks := 0
var _rows := {}
var _upgrade_rows := {}
var _flash := 0.0
var _shake := 0.0
var _pops: Array[Control] = []
var _pop_time := {}

@onready var _safe: MarginContainer = $Safe
@onready var _glow: Label = $Safe/Column/Top/GlowLabel
@onready var _rate: Label = $Safe/Column/Top/RateLabel
@onready var _embers: Label = $Safe/Column/Top/EmbersLabel
@onready var _gather: Button = $Safe/Column/GatherButton
@onready var _page_title: Label = $Safe/Column/Header/PageTitle
@onready var _mode: Button = $Safe/Column/Header/BuyModeButton
@onready var _producer_page: ScrollContainer = $Safe/Column/ProducerPage
@onready var _producer_list: VBoxContainer = $Safe/Column/ProducerPage/List
@onready var _upgrade_page: ScrollContainer = $Safe/Column/UpgradePage
@onready var _upgrade_list: VBoxContainer = $Safe/Column/UpgradePage/List
@onready var _bar: HBoxContainer = $Safe/Column/Bar
@onready var _producers_tab: Button = $Safe/Column/Bar/ProducersTab
@onready var _upgrades_tab: Button = $Safe/Column/Bar/UpgradesTab
@onready var _dawn_button: Button = $Safe/Column/Bar/DawnButton
@onready var _settings_button: Button = $Safe/Column/Bar/SettingsButton
@onready var _flash_rect: ColorRect = $Flash
@onready var _welcome: PanelContainer = $WelcomePanel
@onready var _welcome_title: Label = $WelcomePanel/Box/Title
@onready var _welcome_message: Label = $WelcomePanel/Box/MessageLabel
@onready var _collect: Button = $WelcomePanel/Box/CollectButton
@onready var _dawn_panel: PanelContainer = $DawnPanel
@onready var _dawn_title: Label = $DawnPanel/Box/Title
@onready var _dawn_message: Label = $DawnPanel/Box/MessageLabel
@onready var _confirm: Button = $DawnPanel/Box/ConfirmButton
@onready var _cancel: Button = $DawnPanel/Box/CancelButton
@onready var _sky: Control = $Sky
@onready var _sfx_buy: AudioStreamPlayer = $SfxBuy
@onready var _sfx_upgrade: AudioStreamPlayer = $SfxUpgrade
@onready var _sfx_dawn: AudioStreamPlayer = $SfxDawn
@onready var _sfx_gather: AudioStreamPlayer = $SfxGather


## Called by Main before the game enters the tree: the data, the flags and the saved economy (Economy.to_dict()).
func setup(game_catalog: Catalog, game_options: LaunchOptions, saved: Dictionary) -> void:
	catalog = game_catalog
	options = game_options
	_saved = saved


func _ready() -> void:
	if catalog == null:
		catalog = Catalog.from_files()
	if options == null:
		options = LaunchOptions.from_command_line()
	_gather.pressed.connect(gather)
	_mode.pressed.connect(next_mode)
	_producers_tab.pressed.connect(show_page.bind("producers"))
	_upgrades_tab.pressed.connect(show_page.bind("upgrades"))
	_dawn_button.pressed.connect(ask_dawn)
	_settings_button.pressed.connect(settings_requested.emit)
	_collect.pressed.connect(_welcome.hide)
	_confirm.pressed.connect(confirm_dawn)
	_cancel.pressed.connect(_dawn_panel.hide)
	# Long translations get a smaller font, so the bar fits a phone screen.
	for button: Button in _bar.get_children():
		button.add_theme_font_size_override("font_size", 14)
	for producer: Dictionary in catalog.producers:
		var row := ProducerRow.new()
		row.setup(producer)
		row.buy_pressed.connect(buy)
		_producer_list.add_child(row)
		_rows[row.id] = row
	for upgrade: Dictionary in catalog.upgrades:
		var row := UpgradeRow.new()
		row.setup(upgrade, catalog)
		row.buy_pressed.connect(buy_upgrade)
		_upgrade_list.add_child(row)
		_upgrade_rows[row.id] = row
	restore(_saved)
	show_page("producers")


## Replaces the economy with a saved one (Economy.to_dict()); an empty one starts a new game.
func restore(saved: Dictionary) -> void:
	economy = Economy.from_dict(catalog, saved)
	economy.bought.connect(_on_bought)
	economy.upgraded.connect(_on_upgraded)
	economy.dawned.connect(_on_dawned)
	_refresh()


func _physics_process(delta: float) -> void:
	_ticks += 1
	economy.tick(delta * options.speed)
	if options.autoplay:
		_play_bot()
	_update_effects(delta)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


## Gather: a press of the big button.
func gather() -> void:
	economy.tap()
	_event("gathered")
	_play(_sfx_gather)
	_pop(_gather)
	_refresh()


## Buys the buy mode's amount of a producer.
func buy(id: String) -> bool:
	if buy_mode == 0:
		return economy.buy_max(id) > 0
	return economy.buy(id, buy_mode)


func buy_upgrade(id: String) -> bool:
	return economy.buy_upgrade(id)


func next_mode() -> void:
	buy_mode = MODES[(MODES.find(buy_mode) + 1) % MODES.size()]
	_refresh()


func show_page(which: String) -> void:
	page = which
	_producer_page.visible = which == "producers"
	_upgrade_page.visible = which == "upgrades"
	_mode.visible = which == "producers"
	_refresh()


## Opens the dawn's panel, which says what it would give.
func ask_dawn() -> void:
	if economy.can_dawn():
		_dawn_panel.show()
		_refresh()


func confirm_dawn() -> void:
	_dawn_panel.hide()
	economy.dawn()


## The time away and what it earned, on the welcome panel (Main calls it after the save is read).
func show_welcome(seconds: float, glow: float) -> void:
	if glow <= 0.0:
		return
	_welcome.set_meta("seconds", seconds)
	_welcome.set_meta("glow", glow)
	_welcome.show()
	_refresh()


## Glow for tests and flows: as if it had been earned.
func add_glow(amount: float) -> void:
	economy.earn(amount)
	_refresh()


func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _play_bot() -> void:
	var action := Bot.act(economy)
	if action.kind == "gather":
		_event("gathered")
		_play(_sfx_gather)
		_pop(_gather)
	if not goal_reached and economy.total_earned >= GOAL_GLOW:
		goal_reached = true
		print("[Run] goal: %s glow after %d dawns" % [Numbers.format(economy.total_earned), economy.dawns])
		finished.emit()


func _refresh() -> void:
	if economy == null or not is_node_ready():
		return
	ProducerRow._set_text(_glow, tr("HUD_GLOW") % Numbers.format(economy.glow))
	ProducerRow._set_text(_rate, tr("HUD_RATE") % Numbers.format_rate(economy.rate()))
	ProducerRow._set_text(_embers, tr("HUD_EMBERS") % [Numbers.format(economy.embers), roundi((economy.ember_multiplier() - 1.0) * 100.0)])
	ProducerRow._set_text(_gather, tr("GATHER") % Numbers.format(economy.tap_value()))
	ProducerRow._set_text(_page_title, tr("PAGE_PRODUCERS" if page == "producers" else "PAGE_UPGRADES"))
	ProducerRow._set_text(_mode, tr(MODE_KEYS[buy_mode]))
	ProducerRow._set_text(_producers_tab, tr("BAR_PRODUCERS"))
	ProducerRow._set_text(_upgrades_tab, tr("BAR_UPGRADES"))
	ProducerRow._set_text(_dawn_button, tr("BAR_DAWN"))
	ProducerRow._set_text(_settings_button, tr("BAR_SETTINGS"))
	_dawn_button.disabled = not economy.can_dawn()
	for row: ProducerRow in _rows.values():
		row.refresh(economy, buy_mode)
	for row: UpgradeRow in _upgrade_rows.values():
		row.refresh(economy)
	if _welcome.visible:
		ProducerRow._set_text(_welcome_title, tr("WELCOME_TITLE"))
		ProducerRow._set_text(_welcome_message, tr("WELCOME_MESSAGE") % [_duration(float(_welcome.get_meta("seconds", 0.0))), Numbers.format(float(_welcome.get_meta("glow", 0.0)))])
		ProducerRow._set_text(_collect, tr("WELCOME_COLLECT"))
	if _dawn_panel.visible:
		ProducerRow._set_text(_dawn_title, tr("DAWN_TITLE"))
		ProducerRow._set_text(_dawn_message, tr("DAWN_MESSAGE") % [Numbers.format(economy.dawn_gain()), roundi(catalog.setting("ember_bonus") * 100.0)])
		ProducerRow._set_text(_confirm, tr("DAWN_CONFIRM"))
		ProducerRow._set_text(_cancel, tr("DAWN_CANCEL"))
	_sky.set("glow", economy.glow)


## 2 h 05 min, or 12 min.
func _duration(seconds: float) -> String:
	var minutes := floori(seconds / 60.0)
	if minutes >= 60:
		return tr("TIME_HOURS") % [floori(minutes / 60.0), minutes % 60]
	return tr("TIME_MINUTES") % minutes


func _on_bought(id: String, _amount: int) -> void:
	_refresh()
	_event("bought")
	_play(_sfx_buy)
	_pop(_rows[id].buy_button())


func _on_upgraded(id: String) -> void:
	_refresh()
	_event("upgraded")
	_play(_sfx_upgrade)
	_pop(_upgrade_rows[id].buy_button())


func _on_dawned(embers: float) -> void:
	print("[Run] dawn %d, %s embers" % [economy.dawns, Numbers.format(economy.embers)])
	_event("dawn")
	_play(_sfx_dawn)
	_flash = FLASH_SECONDS
	_feedback("flash")
	_shake = SHAKE_SECONDS
	_feedback("shake")
	_refresh()
	dawned.emit(embers)


func _update_effects(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	_flash_rect.color.a = 0.6 * _flash / FLASH_SECONDS
	_shake = maxf(_shake - delta, 0.0)
	var strength := 14.0 * _shake / SHAKE_SECONDS
	_safe.position = Vector2(sin(_ticks * 1.7) * strength, cos(_ticks * 2.3) * strength)
	for control in _pops.duplicate():
		var left: float = _pop_time[control] - delta
		_pop_time[control] = left
		control.scale = Vector2.ONE * (1.0 + 0.12 * maxf(left, 0.0) / POP_SECONDS)
		if left <= 0.0:
			_pops.erase(control)
			_pop_time.erase(control)


func _pop(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	if not control in _pops:
		_pops.append(control)
	_pop_time[control] = POP_SECONDS
	_feedback("pop")


func _play(player: AudioStreamPlayer) -> void:
	player.play()
	_feedback("sfx")


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func stop_sounds() -> void:
	for player: AudioStreamPlayer in [_sfx_buy, _sfx_upgrade, _sfx_dawn, _sfx_gather]:
		player.stop()
