extends Control
## The shrine between runs: banked embers buy vigor, each level one more hp for the wick in every run after. Main saves
## the bank when the screen closes.

signal closed

var _save: Dictionary

@onready var _title: Label = $Box/Title
@onready var _embers: Label = $Box/EmbersLabel
@onready var _vigor_label: Label = $Box/VigorLabel
@onready var _vigor: Button = $Box/VigorButton
@onready var _back: Button = $Box/BackButton


func setup(save: Dictionary) -> void:
	_save = save


func _ready() -> void:
	if _save.is_empty():
		_save = SaveStore.defaults()
	_vigor.pressed.connect(buy_vigor)
	_back.pressed.connect(closed.emit)
	_refresh_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func buy_vigor() -> void:
	if Meta.buy_vigor(_save):
		_refresh_text()


func _refresh_text() -> void:
	var level := int(_save.meta.vigor)
	_title.text = tr("SHRINE_TITLE")
	_embers.text = tr("SHRINE_EMBERS") % int(_save.meta.embers)
	_vigor_label.text = tr("SHRINE_VIGOR") % [level, Meta.VIGOR_MAX, Meta.max_hp(_save)]
	_vigor.text = tr("SHRINE_BUY") % Meta.vigor_cost(level) if level < Meta.VIGOR_MAX else tr("SHRINE_FULL")
	_vigor.disabled = level >= Meta.VIGOR_MAX or int(_save.meta.embers) < Meta.vigor_cost(level)
	_back.text = tr("SHRINE_BACK")
