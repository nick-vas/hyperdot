extends Control
## One button per track, open once the track before was finished in the top places, with each track's best lap.

signal chosen(id: int)
signal closed

var _tracks: Tracks
var _unlocked := 1
var _best := {}

@onready var _title: Label = $Box/Title
@onready var _grid: GridContainer = $Box/Grid
@onready var _back: Button = $Box/BackButton


func setup(tracks: Tracks, unlocked: int, best: Dictionary) -> void:
	_tracks = tracks
	_unlocked = unlocked
	_best = best


func _ready() -> void:
	if _tracks == null:
		_tracks = Tracks.from_files()
	for row: Dictionary in _tracks.rows:
		var id := int(row.get("id", 0))
		var button := Button.new()
		button.name = "Track%dButton" % id
		button.custom_minimum_size = Vector2(420, 88)
		button.add_theme_font_size_override("font_size", 26)
		button.disabled = id > _unlocked
		button.pressed.connect(chosen.emit.bind(id))
		button.set_meta("track", row)
		_grid.add_child(button)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SELECT_TITLE")
	_back.text = tr("SELECT_BACK")
	for button: Button in _grid.get_children():
		var row: Dictionary = button.get_meta("track")
		var id := str(int(row.get("id", 0)))
		var name_text := tr(str(row.get("name", "")))
		if _best.has(id):
			name_text += "  " + tr("SELECT_BEST") % Race.format_ms(int(_best[id]))
		button.text = name_text
