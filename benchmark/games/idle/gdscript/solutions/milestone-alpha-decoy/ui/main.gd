extends Control
## The holder of the hive and of the screen over it (settings), and the keeper of the save. It reads the save
## at start and pays the time away, and writes it every autosave interval, after a dawn, and when the game is closed,
## sent to the background or loses focus: a phone or a browser tab may never come back to say goodbye.

const GAME_SCENE := preload("res://game/game.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")

## Where the save goes; tests point it elsewhere before Main enters the tree.
var save_path := SaveStore.DEFAULT_PATH
## Unix seconds now. Tests replace it, as a player replaces the phone's clock.
var clock := func() -> float: return Time.get_unix_time_from_system()
var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var catalog: Catalog
var game: Control
## The latest time the game has seen: what the next save keeps for the next offline payment.
var seen_at := 0.0
var _since_save := 0.0
var _screen: Node


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	store = SaveStore.new(save_path)
	store.enabled = not options.no_save
	save = store.read()
	apply_settings(save.settings)
	catalog = Catalog.from_files()
	game = GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(catalog, options, save.economy)
	game.settings_requested.connect(show_settings)
	game.dawned.connect(_on_dawned)
	add_child(game)
	_pay_time_away()


## Pays the economy for the time since the save, as Offline allows, and shows what it earned.
func _pay_time_away() -> void:
	var now: float = clock.call()
	if float(save.saved_at) <= 0.0:
		seen_at = now
		return
	seen_at = Offline.seen_at(float(save.saved_at), now)
	var away := Offline.apply(game.economy, float(save.saved_at), now)
	game.show_welcome(away.seconds, away.glow)


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


## Writes the save now: the economy, the latest time seen and the settings.
func save_now() -> bool:
	seen_at = Offline.seen_at(seen_at, clock.call())
	save.economy = game.economy.to_dict()
	save.saved_at = seen_at
	return store.write(save)


func _process(delta: float) -> void:
	_since_save += delta
	if _since_save >= catalog.setting("autosave_seconds"):
		_since_save = 0.0
		save_now()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			save_now()


func show_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	settings.name = "Settings"
	settings.setup(save)
	settings.closed.connect(_on_settings_closed)
	_show(settings)


## Closes whatever screen is over the hive.
func close_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
		_screen = null
	game.visible = true


func _show(screen: Node) -> void:
	close_screen()
	game.visible = false
	_screen = screen
	add_child(screen)


func _on_settings_closed() -> void:
	save_now()
	close_screen()


func _on_dawned(_embers: float) -> void:
	save_now()
