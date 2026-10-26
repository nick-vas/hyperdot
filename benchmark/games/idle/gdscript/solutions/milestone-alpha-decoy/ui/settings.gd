extends Control
## Volume and language. Changes apply at once; Main saves them when the screen closes.

signal closed

## Each language's own name, the same in every table.
const LANGUAGE_NAMES := {"en": "LANG_EN", "de": "LANG_DE", "fr": "LANG_FR"}

var _save: Dictionary

@onready var _title: Label = $Safe/Box/Title
@onready var _volume_label: Label = $Safe/Box/VolumeLabel
@onready var _volume: HSlider = $Safe/Box/VolumeSlider
@onready var _language_label: Label = $Safe/Box/LanguageLabel
@onready var _languages: HBoxContainer = $Safe/Box/Languages
@onready var _back: Button = $Safe/Box/BackButton
@onready var _version: Label = $Safe/Box/VersionLabel


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
		button.custom_minimum_size = Vector2(0, 88)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 26)
		button.set_meta("locale", locale)
		button.pressed.connect(set_locale.bind(locale))
		_languages.add_child(button)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SETTINGS_TITLE")
	_volume_label.text = tr("SETTINGS_VOLUME")
	_language_label.text = tr("SETTINGS_LANGUAGE")
	_back.text = tr("SETTINGS_BACK")
	_version.text = tr("SETTINGS_VERSION") % ProjectSettings.get_setting("application/config/version", "")
	for button: Button in _languages.get_children():
		var locale := str(button.get_meta("locale"))
		button.text = tr(LANGUAGE_NAMES.get(locale, locale))


func set_locale(locale: String) -> void:
	_save.settings.locale = locale
	TranslationServer.set_locale(locale)


func _on_volume_changed(value: float) -> void:
	_save.settings.volume = value
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001)))
