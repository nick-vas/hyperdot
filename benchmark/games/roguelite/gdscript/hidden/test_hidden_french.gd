extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: French, every visible text translated.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(TranslationServer.get_loaded_locales(), "fr")


func test_hidden_the_hud_and_floors_read_in_french():
	TranslationServer.set_locale("fr")
	for key in ["MENU_START", "MENU_SHRINE", "HUD_ENEMIES", "HUD_STAIRS_OPEN", "RUN_LOST", "RUN_AGAIN", "PAUSE_RESUME", "SHRINE_TITLE"]:
		var french := tr(key)
		TranslationServer.set_locale("en")
		var english := tr(key)
		TranslationServer.set_locale("fr")
		assert_ne(french, key, "%s has a French text" % key)
		assert_ne(french, english, "%s is not left in English" % key)
	var floors := Floors.from_files()
	for number in range(1, floors.count() + 1):
		assert_ne(tr(str(floors.spec(number).name)), str(floors.spec(number).name))


func test_hidden_the_menu_reads_in_french():
	var main: Control = load("res://main.tscn").instantiate()
	add_child_autofree(main)
	await wait_process_frames(2)
	TranslationServer.set_locale("fr")
	await wait_process_frames(2)
	assert_eq(main.get_node("Menu/StartButton").text, "Descendre")
