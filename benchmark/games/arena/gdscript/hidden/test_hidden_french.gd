extends GutTest
## Hidden check for the beta milestone: French, every key translated, the HUD and the menus in French.

func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_true("fr" in TranslationServer.get_loaded_locales())


func test_hidden_every_key_has_french():
	var file := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	var header := file.get_csv_line()
	var fr := Array(header).find("fr")
	assert_gt(fr, 0, "an fr column")
	var line := 1
	while not file.eof_reached():
		var cells := file.get_csv_line()
		line += 1
		if cells.size() <= 1 and (cells.is_empty() or cells[0] == ""):
			continue
		assert_true(cells.size() > fr and cells[fr].strip_edges() != "", "line %d (%s) has French" % [line, cells[0]])


func test_hidden_the_hud_speaks_french():
	TranslationServer.set_locale("fr")
	var game: Node2D = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(ArenaMatch.WARMUP_TICKS + 4)
	var label: String = game.get_node("HUD/RoundLabel").text
	assert_ne(label, "Round 1", "the round label is in French")
	assert_true(label.contains("1"), "and still shows the round: %s" % label)
