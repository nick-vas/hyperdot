extends Control
## The end of the championship: every track finished in the top places.

signal menu_pressed

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/Message
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("VICTORY_TITLE")
	_message.text = tr("VICTORY_MESSAGE")
	_menu.text = tr("VICTORY_MENU")
