extends Control
## The campaign's maps, one button each: open once the map before is cleared, with the stars of a cleared one.

signal map_chosen(index: int)
signal closed

var _catalog: Catalog
var _save: Dictionary

@onready var _title: Label = $Box/Title
@onready var _grid: GridContainer = $Box/Grid
@onready var _back: Button = $Box/BackButton


func setup(catalog: Catalog, save: Dictionary) -> void:
	_catalog = catalog
	_save = save


func _ready() -> void:
	if _catalog == null:
		_catalog = Catalog.from_files()
	if _save.is_empty():
		_save = SaveStore.defaults()
	for index in range(1, _catalog.map_count() + 1):
		var button := Button.new()
		button.name = "Map%dButton" % index
		button.custom_minimum_size = Vector2(520, 88)
		button.add_theme_font_size_override("font_size", 24)
		button.disabled = not Progress.is_unlocked(_save, _catalog, index)
		button.pressed.connect(map_chosen.emit.bind(index))
		_grid.add_child(button)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func _refresh_text() -> void:
	_title.text = tr("SELECT_TITLE")
	_back.text = tr("SELECT_BACK")
	for index in range(1, _grid.get_child_count() + 1):
		var button: Button = _grid.get_child(index - 1)
		var row := _catalog.map_at(index)
		button.text = tr("SELECT_MAP") % [index, tr(str(row.name))]
		var stars := Progress.stars(_save, str(row.id))
		if stars > 0:
			button.text += "  " + tr("SELECT_STARS") % stars
