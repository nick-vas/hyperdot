extends Control
## The title menu, and the holder of whatever screen is showing: the game, the join screen or settings.
## Screens are children of Main rather than scene changes, so the settings and the network session live in one place.
## Started as a dedicated server or a soak process (--server, --soak-role), it shows nothing and runs Headless instead.

const GAME_SCENE := preload("res://game/game.tscn")
const JOIN_SCENE := preload("res://ui/join.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const HEADLESS := preload("res://game/headless.gd")
## Physics frames a bot run shows the finished match.
const AUTOPLAY_QUIT_FRAMES := 60

var options: LaunchOptions
var store: SettingsStore
var settings: Dictionary
var session: NetSession
var courts: Array[Court] = []
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _play: Button = $Menu/PlayButton
@onready var _host: Button = $Menu/HostButton
@onready var _join: Button = $Menu/JoinButton
@onready var _settings: Button = $Menu/SettingsButton
@onready var _quit: Button = $Menu/QuitButton
@onready var _status: Label = $StatusLabel
@onready var _version: Label = $Menu/VersionLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	if options.server or options.soak_role != "":
		_menu.visible = false
		var headless: Node = HEADLESS.new()
		headless.name = "Headless"
		headless.setup(options)
		add_child(headless)
		return
	store = SettingsStore.new()
	store.enabled = not options.no_save
	settings = store.read()
	apply_settings(settings)
	# The courts are read once, here: every match and every rematch plays them.
	courts = Court.load_all()
	_play.pressed.connect(start_game.bind("local"))
	_host.pressed.connect(start_game.bind("host"))
	_join.pressed.connect(show_join)
	_settings.pressed.connect(show_settings)
	_quit.pressed.connect(get_tree().quit)
	_refresh_text()
	show_menu()
	if options.autoplay:
		start_game("local")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and store != null:
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_play.text = tr("MENU_PLAY")
	_host.text = tr("MENU_HOST")
	_join.text = tr("MENU_JOIN")
	_settings.text = tr("MENU_SETTINGS")
	_quit.text = tr("MENU_QUIT")
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(values: Dictionary) -> void:
	TranslationServer.set_locale(str(values.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(values.get("volume", 1.0)), 0.0001)))


## Starts a match: "local" against bots, "host" for others to join on the port, "join" to a server at an address.
func start_game(mode: String, address := "") -> void:
	_status.text = ""
	if mode != "local":
		_open_session()
		var err := session.host(options.port) if mode == "host" else session.join(address, options.port)
		if err != OK:
			_close_session()
			show_menu()
			_status.text = tr("MENU_NET_FAILED") % error_string(err)
			return
		session.disconnected.connect(_on_disconnected)
	var game := GAME_SCENE.instantiate()
	game.name = "Game"
	game.setup(mode, options, session, courts)
	game.match_over.connect(_on_match_over)
	game.menu_requested.connect(show_menu)
	_show(game)


func show_join() -> void:
	var join := JOIN_SCENE.instantiate()
	join.name = "Join"
	join.join_pressed.connect(func(address: String) -> void: start_game("join", address))
	join.closed.connect(show_menu)
	_show(join)


func show_settings() -> void:
	var screen := SETTINGS_SCENE.instantiate()
	screen.name = "Settings"
	screen.setup(settings)
	screen.closed.connect(_on_settings_closed)
	_show(screen)


func show_menu() -> void:
	_close_screen()
	_close_session()
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


func _open_session() -> void:
	_close_session()
	session = NetSession.new()
	session.name = "Net"
	add_child(session)


func _close_session() -> void:
	if session != null:
		session.close()
		remove_child(session)
		session.queue_free()
		session = null


func _on_disconnected(_reason: String) -> void:
	show_menu.call_deferred()
	_status.text = tr("MENU_NET_LOST")


func _on_settings_closed() -> void:
	store.write(settings)
	show_menu()


func _on_match_over(won: bool) -> void:
	settings.played = int(settings.played) + 1
	if won:
		settings.won = int(settings.won) + 1
	store.write(settings)
	if options.autoplay:
		_end_bot_run()


## A bot run shows the result for a moment, then frees the game and lets its sounds stop before the engine exits.
func _end_bot_run() -> void:
	for i in AUTOPLAY_QUIT_FRAMES:
		await get_tree().physics_frame
	_close_screen()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit()
