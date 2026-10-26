extends CanvasLayer
## The panel at the end of a run: out or through, how deep and how many embers go to the bank; Descend again or Back to
## menu.

signal again_pressed
signal menu_pressed

var _won := false
var _floor := 1
var _embers := 0

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
	_title.text = tr("RUN_WON") if _won else tr("RUN_LOST")
	_message.text = tr("RUN_WON_MESSAGE") % _embers if _won else tr("RUN_LOST_MESSAGE") % [_floor, _embers]
	_again.text = tr("RUN_AGAIN")
	_menu.text = tr("RUN_MENU")


## embers: what goes to the bank.
func open(won: bool, floor_number: int, embers: int) -> void:
	_won = won
	_floor = floor_number
	_embers = embers
	_refresh_text()
	visible = true


func close() -> void:
	visible = false
