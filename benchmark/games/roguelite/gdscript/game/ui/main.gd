extends Control
## The title menu, and the holder of whatever screen is showing: the game, the shrine, settings or credits. Screens are
## children of Main rather than scene changes, so the save and the data live in one place.

const GAME_SCENE := preload("res://game/game.tscn")
const SHRINE_SCENE := preload("res://ui/shrine.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const CREDITS_SCENE := preload("res://ui/credits.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var floors: Floors
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _embers: Label = $Menu/EmbersLabel
@onready var _start: Button = $Menu/StartButton
@onready var _continue: Button = $Menu/ContinueButton
@onready var _shrine: Button = $Menu/ShrineButton
@onready var _settings: Button = $Menu/SettingsButton
@onready var _credits: Button = $Menu/CreditsButton
@onready var _quit: Button = $Menu/QuitButton
@onready var _version: Label = $Menu/VersionLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	store = SaveStore.new()
	store.enabled = not options.no_save
	save = store.read()
	apply_settings(save.settings)
	floors = Floors.from_files()
	_start.pressed.connect(start_run)
	_continue.pressed.connect(continue_run)
	_shrine.pressed.connect(show_shrine)
	_settings.pressed.connect(show_settings)
	_credits.pressed.connect(show_credits)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()
	show_menu()
	if options.autoplay:
		start_run()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_embers.text = tr("MENU_EMBERS") % [int(save.meta.embers), int(save.meta.best_floor)]
	_start.text = tr("MENU_START")
	_continue.text = tr("MENU_CONTINUE")
	_shrine.text = tr("MENU_SHRINE")
	_settings.text = tr("MENU_SETTINGS")
	_credits.text = tr("MENU_CREDITS")
	_quit.text = tr("MENU_QUIT")
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


## A new run, with the vigor bought at the shrine.
func start_run() -> void:
	_start_game({})


## Carries on the run kept in the save.
func continue_run() -> void:
	if typeof(save.run) == TYPE_DICTIONARY:
		_start_game(save.run)


func _start_game(saved: Dictionary) -> void:
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(floors, options, Meta.max_hp(save), saved)
	game.run_over.connect(_on_run_over)
	game.checkpoint.connect(_on_checkpoint)
	game.finished.connect(_on_finished)
	game.menu_requested.connect(show_menu)
	_show(game)


func show_shrine() -> void:
	var shrine := SHRINE_SCENE.instantiate()
	shrine.name = "Shrine"
	shrine.setup(save)
	shrine.closed.connect(_on_screen_closed)
	_show(shrine)


func show_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	settings.name = "Settings"
	settings.setup(save)
	settings.closed.connect(_on_screen_closed)
	_show(settings)


func show_credits() -> void:
	var credits := CREDITS_SCENE.instantiate()
	credits.name = "Credits"
	credits.closed.connect(show_menu)
	_show(credits)


func show_menu() -> void:
	_close_screen()
	_menu.visible = true
	_continue.visible = typeof(save.run) == TYPE_DICTIONARY
	_refresh_text()


func _show(screen: Node) -> void:
	_close_screen()
	_menu.visible = false
	_screen = screen
	add_child(screen)


func _close_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null


func _on_screen_closed() -> void:
	store.write(save)
	show_menu()


## A floor began: the run is kept so Continue can carry on from here.
func _on_checkpoint(data: Dictionary) -> void:
	save.run = data
	store.write(save)


func _on_run_over(won: bool, floor_number: int, embers: int) -> void:
	Meta.bank(save, embers, floor_number, won)
	save.run = null
	store.write(save)


func _on_finished() -> void:
	if options.autoplay:
		# A bot run ends here; free the game first so nothing is left in use when the engine exits.
		_close_screen.call_deferred()
		_quit_after_frames(3)


## Lets the freed game's sounds stop before the engine exits, so the exit is clean.
func _quit_after_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().quit()
