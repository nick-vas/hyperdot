extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships French, with every key the menus, HUD and tracks
## use translated.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(Array(TranslationServer.get_loaded_locales()), "fr")


func test_hidden_the_menus_and_tracks_are_in_french():
	TranslationServer.set_locale("fr")
	for key in ["MENU_START", "MENU_SETTINGS", "MENU_QUIT", "SELECT_TITLE", "PAUSE_RESUME", "TRACK_1", "TRACK_2", "TRACK_3", "SETTINGS_TITLE"]:
		var french := tr(key)
		assert_ne(french, key, "%s has a French text" % key)
		TranslationServer.set_locale("en")
		assert_ne(french, tr(key), "%s differs from the English" % key)
		TranslationServer.set_locale("fr")
