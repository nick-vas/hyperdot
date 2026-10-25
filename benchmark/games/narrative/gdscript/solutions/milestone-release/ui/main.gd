extends Control
## The title menu, and the holder of whatever screen is showing: the story, settings or credits. Screens are children
## of Main rather than scene changes, so the save and the story data live in one place.

const STORY_SCENE := preload("res://story/story.tscn")
const SETTINGS_SCENE := preload("res://ui/settings.tscn")
const CREDITS_SCENE := preload("res://ui/credits.tscn")

var options: LaunchOptions
var store: SaveStore
var save: Dictionary
var graph: StoryGraph
var _screen: Node

@onready var _menu: Control = $Menu
@onready var _title: Label = $Menu/Title
@onready var _new: Button = $Menu/NewButton
@onready var _continue: Button = $Menu/ContinueButton
@onready var _settings: Button = $Menu/SettingsButton
@onready var _credits: Button = $Menu/CreditsButton
@onready var _quit: Button = $Menu/QuitButton
@onready var _endings: Label = $Menu/EndingsLabel
@onready var _version: Label = $Menu/VersionLabel


func _ready() -> void:
	options = LaunchOptions.from_command_line()
	store = SaveStore.new()
	store.enabled = not options.no_save
	save = store.read()
	apply_settings(save.settings)
	graph = StoryGraph.from_files()
	_new.pressed.connect(new_story)
	_continue.pressed.connect(continue_story)
	_settings.pressed.connect(show_settings)
	_credits.pressed.connect(show_credits)
	_quit.pressed.connect(get_tree().quit)
	show_menu()
	if options.autoplay:
		new_story()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("MENU_TITLE")
	_new.text = tr("MENU_NEW")
	_continue.text = tr("MENU_CONTINUE")
	_settings.text = tr("MENU_SETTINGS")
	_credits.text = tr("MENU_CREDITS")
	_quit.text = tr("MENU_QUIT")
	_endings.text = tr("MENU_ENDINGS") % [save.endings.size(), graph.ending_ids.size()]
	_version.text = tr("MENU_VERSION") % ProjectSettings.get_setting("application/config/version", "")


static func apply_settings(settings: Dictionary) -> void:
	TranslationServer.set_locale(str(settings.get("locale", "en")))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.get("volume", 1.0)), 0.0001)))


## A story from the first line; a story in progress is given up.
func new_story() -> void:
	_start_story({})


## Carries on the story kept in the save.
func continue_story() -> void:
	if typeof(save.story) == TYPE_DICTIONARY:
		_start_story(save.story)


func _start_story(saved: Dictionary) -> void:
	var screen := STORY_SCENE.instantiate()
	screen.name = "Story"
	screen.setup(graph, options, save.endings, saved)
	screen.checkpoint.connect(_on_checkpoint)
	screen.ending_found.connect(_on_ending_found)
	screen.finished.connect(_on_finished)
	screen.menu_requested.connect(show_menu)
	_show(screen)


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
	_continue.visible = typeof(save.story) == TYPE_DICTIONARY
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


func _on_settings_closed() -> void:
	store.write(save)
	show_menu()


## A line was shown: the story is kept so Continue can carry on from here.
func _on_checkpoint(data: Dictionary) -> void:
	save.story = data
	store.write(save)


func _on_ending_found(ending_id: String) -> void:
	SaveStore.record_ending(save, ending_id)
	save.story = null
	store.write(save)


func _on_finished() -> void:
	# A bot run ends here; free the story first so nothing is left in use when the engine exits.
	_close_screen.call_deferred()
	_quit_after_frames(3)


## Lets the freed story's sounds stop before the engine exits, so the exit is clean.
func _quit_after_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().quit()
