extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the Star Loom, German throughout, the bar on a phone in German,
## and the bot.


func test_hidden_five_producers():
	var catalog := Catalog.from_files()
	var ids := catalog.producers.map(func(p: Dictionary) -> String: return str(p.id))
	assert_eq(ids, ["wick_moth", "glow_snail", "firefly_choir", "moon_lily", "star_loom"])
	assert_false(catalog.upgrade("star_thread").is_empty())


func test_hidden_every_text_has_german():
	var csv := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	var header := csv.get_csv_line()
	var de := Array(header).find("de")
	assert_gt(de, 0, "a de column")
	var rows := 0
	while not csv.eof_reached():
		var line := csv.get_csv_line()
		if line.size() <= 1:
			continue
		rows += 1
		assert_ne(line[de].strip_edges(), "", "%s in German" % line[0])
	assert_gt(rows, 40)


func test_hidden_german_names_on_screen():
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	var game: Control = load("res://game/game.tscn").instantiate()
	add_child_autofree(game)
	await wait_physics_frames(2)
	var name_label: Label = game.get_node("Safe/Column/ProducerPage/List/WickMothRow/Box/Info/NameLabel")
	assert_ne(name_label.text, "Wick Moth")
	assert_ne(name_label.text, "PRODUCER_WICK_MOTH")
	assert_ne(game.get_node("Safe/Column/Bar/SettingsButton").text, "Settings")
	TranslationServer.set_locale(locale)


func test_hidden_the_bot_plays_from_the_command_line():
	var options := LaunchOptions.parse(PackedStringArray(["--autoplay", "--speed=60", "--no-save"]))
	assert_true(options.autoplay)
	assert_eq(options.speed, 60.0)
	assert_true(options.no_save)
	var economy := Economy.new(Catalog.from_files())
	for second in 3600:
		Bot.act(economy)
		economy.tick(1.0)
	assert_gte(economy.dawns, 3)
