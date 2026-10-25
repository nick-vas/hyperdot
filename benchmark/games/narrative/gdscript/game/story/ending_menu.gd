extends CanvasLayer
## The panel over an ending: its title, how many endings are found, Cross again and Back to menu.

signal again_pressed
signal menu_pressed

var _title_key := ""
var _found := 0
var _total := 0

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _again: Button = $Box/AgainButton
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	visible = false
	_again.pressed.connect(again_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr(_title_key) if not _title_key.is_empty() else ""
	_message.text = tr("MENU_ENDINGS") % [_found, _total]
	_again.text = tr("ENDING_AGAIN")
	_menu.text = tr("ENDING_MENU")


func open(title_key: String, found: int, total: int) -> void:
	_title_key = title_key
	_found = found
	_total = total
	_refresh_text()
	visible = true
	_again.grab_focus.call_deferred()


func close() -> void:
	visible = false
