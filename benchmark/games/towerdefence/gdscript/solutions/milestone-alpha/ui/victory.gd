extends Control
## The end of the campaign: every map cleared, and the stars of the whole save counted.

signal menu_pressed

var _total := 0

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _menu: Button = $Box/MenuButton


func setup(total_stars: int) -> void:
	_total = total_stars


func _ready() -> void:
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("VICTORY_TITLE")
	_message.text = tr("VICTORY_MESSAGE") % _total
	_menu.text = tr("VICTORY_MENU")
