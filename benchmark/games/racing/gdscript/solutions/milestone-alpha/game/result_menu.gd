extends CanvasLayer
## The panel at the end of a race: the place, the best lap, and Next (when the place opens the next track), Retry and
## Menu.

signal next_pressed
signal retry_pressed
signal menu_pressed

var _place := 0
var _cars := 0
var _best_ms := 0

@onready var _title: Label = $Box/Title
@onready var _place_label: Label = $Box/PlaceLabel
@onready var _time_label: Label = $Box/TimeLabel
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


func open(place: int, cars: int, best_ms: int, can_go_on: bool) -> void:
	_place = place
	_cars = cars
	_best_ms = best_ms
	_next.visible = can_go_on
	visible = true
	_refresh_text()


func close() -> void:
	visible = false


func _refresh_text() -> void:
	_title.text = tr("RESULT_TITLE")
	_place_label.text = tr("RESULT_PLACE") % [_place, _cars]
	_time_label.text = tr("RESULT_BEST") % Race.format_ms(_best_ms)
	_next.text = tr("RESULT_NEXT")
	_retry.text = tr("RESULT_RETRY")
	_menu.text = tr("RESULT_MENU")
