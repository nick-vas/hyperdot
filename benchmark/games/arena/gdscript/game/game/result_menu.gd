extends CanvasLayer
## The panel over a finished match: won or lost, who won by how much, Rematch (not for a joined player, whose host
## decides) and Back to menu.

signal rematch_pressed
signal menu_pressed

var _won := false
var _winner := 1
var _score := 0
var _second := 0

@onready var _title: Label = $Box/Title
@onready var _message: Label = $Box/MessageLabel
@onready var _rematch: Button = $Box/RematchButton
@onready var _menu: Button = $Box/MenuButton


func _ready() -> void:
	visible = false
	_rematch.pressed.connect(rematch_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("RESULT_WON") if _won else tr("RESULT_LOST")
	_message.text = tr("RESULT_MESSAGE") % [_winner, _score, _second]
	_rematch.text = tr("RESULT_REMATCH")
	_menu.text = tr("RESULT_MENU")


## winner: the winning player's number (slot + 1); can_rematch: false for a joined player.
func open(won: bool, winner: int, score: int, second: int, can_rematch: bool) -> void:
	_won = won
	_winner = winner
	_score = score
	_second = second
	_rematch.visible = can_rematch
	_refresh_text()
	visible = true


func close() -> void:
	visible = false
