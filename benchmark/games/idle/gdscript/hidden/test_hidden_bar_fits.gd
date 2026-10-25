extends GutTest
## Hidden check for the beta's fix-bug: on a portrait phone, every button of the bottom bar is on the screen in every
## language the game ships, and in a made-up one whose words are longer still.

const PHONE := Vector2i(1080, 2400)

var _size: Vector2i
var _locale: String
var _long: Translation


func before_all():
	_size = get_tree().root.size
	_locale = TranslationServer.get_locale()
	_long = Translation.new()
	_long.locale = "xx"
	for key in ["BAR_PRODUCERS", "BAR_UPGRADES", "BAR_DAWN", "BAR_SETTINGS"]:
		_long.add_message(key, "Morgendämmerungsverbesserungen")
	TranslationServer.add_translation(_long)


func after_all():
	TranslationServer.remove_translation(_long)
	TranslationServer.set_locale(_locale)
	get_tree().root.size = _size


func _check(locale: String) -> void:
	TranslationServer.set_locale(locale)
	get_tree().root.size = PHONE
	var game: Control = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(3)
	await wait_frames(3)
	var screen := game.get_viewport().get_visible_rect()
	for name in ["ProducersTab", "UpgradesTab", "DawnButton", "SettingsButton"]:
		var button: Button = game.get_node("Safe/Column/Bar/" + name)
		var rect := button.get_global_rect()
		assert_true(screen.encloses(rect.grow(-0.5)), "%s in %s: %s is outside the screen %s" % [name, locale, rect, screen])
		assert_gte(rect.size.x, 60.0, "%s in %s is still a button" % [name, locale])
	assert_lte(game.get_node("Safe/Column").size.x, screen.size.x, "the column fits the screen in %s" % locale)


func test_hidden_the_bar_fits_in_english():
	await _check("en")


func test_hidden_the_bar_fits_in_german():
	await _check("de")


func test_hidden_the_bar_fits_longer_words():
	await _check("xx")
