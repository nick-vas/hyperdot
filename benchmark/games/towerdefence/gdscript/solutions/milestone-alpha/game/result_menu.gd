extends CanvasLayer
## The panel over a finished map: cleared (with its stars) or lost, Next (Finish after the last map) once cleared, Retry,
## and Back to menu.

signal next_pressed
signal retry_pressed
signal menu_pressed

var _won := false
var _stars := 0
var _next_key := "RESULT_NEXT"

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _next: Button = $Box/NextButton
@onready var _retry: Button = $Box/RetryButton
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	visible = false
	_next.pressed.connect(next_pressed.emit)
	_retry.pressed.connect(retry_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("RESULT_WON") if _won else tr("RESULT_LOST")
	_message.text = tr("RESULT_WON_MESSAGE") % _stars if _won else tr("RESULT_LOST_MESSAGE")
	_next.text = tr(_next_key)
	_retry.text = tr("RESULT_RETRY")
	_menu.text = tr("RESULT_MENU")


## stars: what the cleared map earned; next_key: the Next button's text key. The button shows only after a win.
func open(won: bool, stars: int, next_key: String) -> void:
	_won = won
	_stars = stars
	_next_key = next_key
	_next.visible = won
	_refresh_text()
	visible = true


func close() -> void:
	visible = false
