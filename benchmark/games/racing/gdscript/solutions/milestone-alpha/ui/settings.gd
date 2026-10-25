extends Control
## Volume, language and the keys. Changes apply at once; Main saves them when the screen closes. A key button waits for
## the next key pressed (Escape keeps the old one); the gamepad's bindings never change.

signal closed

## Each language's own name, the same in every table.
const LANGUAGE_NAMES := {"en": "LANG_EN", "fr": "LANG_FR", "de": "LANG_DE"}
const ACTION_KEYS := {"accelerate": "CONTROL_ACCELERATE", "brake": "CONTROL_BRAKE", "steer_left": "CONTROL_LEFT", "steer_right": "CONTROL_RIGHT"}

## The action waiting for its new key, "" when none is.
var waiting := ""
var _save: Dictionary

@onready var _title: Label = $Box/Title
@onready var _volume_label: Label = $Box/VolumeLabel
@onready var _volume: HSlider = $Box/VolumeSlider
@onready var _language_label: Label = $Box/LanguageLabel
@onready var _languages: HBoxContainer = $Box/Languages
@onready var _controls_label: Label = $Box/ControlsLabel
@onready var _controls: GridContainer = $Box/Controls
@onready var _back: Button = $Box/BackButton


func setup(save: Dictionary) -> void:
	_save = save


func _ready() -> void:
	if _save.is_empty():
		_save = SaveStore.defaults()
	_volume.value = float(_save.settings.volume)
	_volume.value_changed.connect(_on_volume_changed)
	# One button per language the game ships, so adding a translation adds its button.
	var locales := Array(TranslationServer.get_loaded_locales())
	locales.sort()
	for locale: String in locales:
		var button := Button.new()
		button.name = "%sButton" % locale.capitalize()
		button.custom_minimum_size = Vector2(150, 64)
		button.set_meta("locale", locale)
		button.pressed.connect(set_locale.bind(locale))
		_languages.add_child(button)
	for action: String in Controls.ACTIONS:
		var label := Label.new()
		label.name = "%sLabel" % action.to_pascal_case()
		label.add_theme_font_size_override("font_size", 22)
		label.set_meta("action", action)
		_controls.add_child(label)
		var button := Button.new()
		button.name = "%sButton" % action.to_pascal_case()
		button.custom_minimum_size = Vector2(180, 56)
		button.set_meta("action", action)
		button.pressed.connect(begin_rebind.bind(action))
		_controls.add_child(button)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SETTINGS_TITLE")
	_volume_label.text = tr("SETTINGS_VOLUME")
	_language_label.text = tr("SETTINGS_LANGUAGE")
	_controls_label.text = tr("SETTINGS_CONTROLS")
	_back.text = tr("SETTINGS_BACK")
	for button: Button in _languages.get_children():
		var locale := str(button.get_meta("locale"))
		button.text = tr(LANGUAGE_NAMES.get(locale, locale))
	for node: Control in _controls.get_children():
		var action := str(node.get_meta("action"))
		if node is Button:
			(node as Button).text = tr("SETTINGS_PRESS_KEY") if action == waiting else Controls.label(action)
		else:
			(node as Label).text = tr(ACTION_KEYS[action])


func set_locale(locale: String) -> void:
	_save.settings.locale = locale
	TranslationServer.set_locale(locale)


func begin_rebind(action: String) -> void:
	waiting = action
	_refresh_text()


## The key pressed while an action waits: it becomes the action's key (Escape cancels). Flows call it directly.
func capture_key(key: int) -> void:
	if waiting == "":
		return
	if key != KEY_ESCAPE:
		Controls.rebind(waiting, key as Key)
		_save.controls = Controls.to_dict()
	waiting = ""
	_refresh_text()


func _input(event: InputEvent) -> void:
	if waiting == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	capture_key(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	get_viewport().set_input_as_handled()


func _on_volume_changed(value: float) -> void:
	_save.settings.volume = value
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001)))
