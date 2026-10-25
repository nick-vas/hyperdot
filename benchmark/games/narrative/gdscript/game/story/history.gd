extends CanvasLayer
## The history panel: every line of this story so far and the choices taken, newest last.

@onready var _title: Label = $Box/Title
@onready var _scroll: ScrollContainer = $Box/Scroll
@onready var _lines: Label = $Box/Scroll/Lines
@onready var _close: Button = $Box/CloseButton


func _ready() -> void:
	visible = false
	_close.pressed.connect(close)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("HISTORY_TITLE")
	_close.text = tr("HISTORY_CLOSE")


func open(lines: PackedStringArray) -> void:
	_lines.text = "\n\n".join(lines)
	visible = true
	_close.grab_focus.call_deferred()
	# The newest line is at the bottom: scroll there once the label has its size.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func close() -> void:
	visible = false
