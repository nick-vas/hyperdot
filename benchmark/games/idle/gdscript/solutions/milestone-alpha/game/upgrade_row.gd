class_name UpgradeRow
extends PanelContainer
## One upgrade on offer: what it multiplies, its price and a button. Shown once its producer is owned often enough,
## hidden once bought.

signal buy_pressed(id: String)

var id := ""
var _upgrade := {}
var _name := Label.new()
var _detail := Label.new()
var _buy := Button.new()


func setup(upgrade: Dictionary, catalog: Catalog) -> void:
	id = str(upgrade.id)
	_upgrade = upgrade
	name = "%sRow" % id.to_pascal_case()
	custom_minimum_size = Vector2(0, 96)
	var box := HBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(info)
	_name.name = "NameLabel"
	_name.add_theme_font_size_override("font_size", 28)
	info.add_child(_name)
	_detail.name = "DetailLabel"
	_detail.add_theme_font_size_override("font_size", 22)
	_detail.modulate = Color(0.85, 0.82, 1.0)
	_detail.set_meta("target_key", _target_key(str(upgrade.target), catalog))
	info.add_child(_detail)
	_buy.name = "BuyButton"
	_buy.custom_minimum_size = Vector2(200, 88)
	_buy.add_theme_font_size_override("font_size", 26)
	_buy.pressed.connect(func() -> void: buy_pressed.emit(id))
	box.add_child(_buy)


func buy_button() -> Button:
	return _buy


func refresh(economy: Economy) -> void:
	visible = economy.upgrade_unlocked(id)
	if not visible:
		return
	ProducerRow._set_text(_name, tr(str(_upgrade.name)))
	ProducerRow._set_text(_detail, tr("UPGRADE_DETAIL") % [tr(str(_detail.get_meta("target_key"))), _times(float(_upgrade.multiplier))])
	ProducerRow._set_text(_buy, Numbers.format(float(_upgrade.cost)))
	_buy.disabled = not economy.can_upgrade(id)


static func _target_key(target: String, catalog: Catalog) -> String:
	if target == "all" or target == "tap":
		return "TARGET_%s" % target.to_upper()
	return str(catalog.producer(target).get("name", target))


## 2 as "2", 1.5 as "1.5".
static func _times(m: float) -> String:
	return str(int(m)) if m == floorf(m) else str(m)
