extends Control
## Joining a match someone hosts: the host's address, then Join.

signal join_pressed(address: String)
signal closed

@onready var _title: Label = $Box/Title
@onready var _address_label: Label = $Box/AddressLabel
@onready var _address: LineEdit = $Box/AddressEdit
@onready var _join: Button = $Box/JoinButton
@onready var _back: Button = $Box/BackButton


func _ready() -> void:
	_join.pressed.connect(_on_join)
	_address.text_submitted.connect(func(_text: String) -> void: _on_join())
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("JOIN_TITLE")
	_address_label.text = tr("JOIN_ADDRESS")
	_join.text = tr("JOIN_JOIN")
	_back.text = tr("JOIN_BACK")


func _on_join() -> void:
	var address := _address.text.strip_edges()
	join_pressed.emit(address if address != "" else "127.0.0.1")
