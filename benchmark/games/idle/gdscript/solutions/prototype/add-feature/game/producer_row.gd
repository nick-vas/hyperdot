class_name ProducerRow
extends PanelContainer
## One producer in the shop: its name, how many are owned and what they make, and a button that buys the amount the
## buy mode asks for at its price. Game refreshes it; it never reads the economy on its own.

signal buy_pressed(id: String)

var id := ""
var _name_key := ""
var _name := Label.new()
var _detail := Label.new()
var _buy := Button.new()


func setup(producer: Dictionary) -> void:
	id = str(producer.id)
	_name_key = str(producer.name)
	name = "%sRow" % id.to_pascal_case()
	custom_minimum_size = Vector2(0, 104)
	var box := HBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(info)
	_name.name = "NameLabel"
	_name.add_theme_font_size_override("font_size", 30)
	info.add_child(_name)
	_detail.name = "DetailLabel"
	_detail.add_theme_font_size_override("font_size", 24)
	_detail.modulate = Color(0.85, 0.82, 1.0)
	info.add_child(_detail)
	_buy.name = "BuyButton"
	_buy.custom_minimum_size = Vector2(230, 96)
	_buy.add_theme_font_size_override("font_size", 26)
	_buy.pressed.connect(func() -> void: buy_pressed.emit(id))
	box.add_child(_buy)


func buy_button() -> Button:
	return _buy


## Shows the producer as the economy has it, for a buy amount of mode (0: as many as the glow pays for).
func refresh(economy: Economy, mode: int) -> void:
	var amount := mode if mode > 0 else maxi(1, economy.max_affordable(id))
	_set_text(_name, tr(_name_key))
	_set_text(_detail, tr("ROW_DETAIL") % [economy.count(id), Numbers.format_rate(economy.producer_rate(id))])
	_set_text(_buy, tr("ROW_BUY") % [amount, Numbers.format(economy.cost(id, amount))])
	_buy.disabled = not economy.can_buy(id, amount)


static func _set_text(control: Control, text: String) -> void:
	if control.get("text") != text:
		control.set("text", text)
