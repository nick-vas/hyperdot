extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, the story included.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(Array(TranslationServer.get_loaded_locales()), "fr")


func test_hidden_menu_and_story_are_translated():
	var graph := StoryGraph.from_files()
	for key in ["MENU_NEW", "SETTINGS_TITLE", graph.node("dock").text, graph.node("end_bell").text, graph.choice("ask_bell").text, "ENDING_BELL"]:
		TranslationServer.set_locale("en")
		var english := TranslationServer.translate(key)
		TranslationServer.set_locale("fr")
		var french := TranslationServer.translate(key)
		assert_ne(french, key, key)
		assert_ne(french, english, key)
