extends Control
## The title menu, and the holder of whatever screen is showing: the map select, the game, settings, credits or victory.
## Screens are children of Main rather than scene changes, so the save and the data live in one place.

const GAME_SCENE := preload("res://game/game.tscn")
const MAP_SELECT_SCENE := preload("res://ui/map_select.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const CREDITS_SCENE := preload("res://ui/credits.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var catalog: Catalog
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _start: Button = $Menu/StartButton
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
	catalog = Catalog.from_files()
	_start.pressed.connect(show_map_select)
	_settings.pressed.connect(show_settings)
	_credits.pressed.connect(show_credits)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()
	show_menu()
	if options.autoplay:
		start_map(options.map)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_start.text = tr("MENU_START")
	_settings.text = tr("MENU_SETTINGS")
	_credits.text = tr("MENU_CREDITS")
	_quit.text = tr("MENU_QUIT")
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


func show_map_select() -> void:
	var select := MAP_SELECT_SCENE.instantiate()
	select.name = "MapSelect"
	select.setup(catalog, save)
	select.map_chosen.connect(start_map)
	select.closed.connect(show_menu)
	_show(select)


func start_map(index: int) -> void:
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(catalog, options, index)
	game.map_over.connect(_on_map_over)
	game.finished.connect(_on_finished)
	game.menu_requested.connect(show_menu)
	_show(game)


func show_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	settings.name = "Settings"
	settings.setup(save)
	settings.closed.connect(_on_settings_closed)
	_show(settings)


func show_credits() -> void:
	var credits := CREDITS_SCENE.instantiate()
	credits.name = "Credits"
	credits.closed.connect(show_menu)
	_show(credits)


func show_menu() -> void:
	_close_screen()
	_menu.visible = true


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


func _on_settings_closed() -> void:
	store.write(save)
	show_menu()


func _on_map_over(level: int, won: bool, lives: int, start_lives: int) -> void:
	if won:
		Progress.record(save, str(catalog.map_at(level).id), lives, start_lives)
		store.write(save)


func _on_finished(victory: bool) -> void:
	if options.autoplay:
		# A bot run ends here; free the game first so nothing is left in use when the engine exits.
		_close_screen.call_deferred()
		_quit_after_frames(3)
		return
	if not victory:
		show_menu.call_deferred()
		return
	var screen := VICTORY_SCENE.instantiate()
	screen.name = "Victory"
	screen.setup(Progress.total_stars(save))
	screen.menu_pressed.connect(show_menu)
	# The game is still inside its own physics step or a button's signal; swap it out once that is over.
	_show.call_deferred(screen)


## Lets the freed game's sounds stop before the engine exits, so the exit is clean.
func _quit_after_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().quit()
