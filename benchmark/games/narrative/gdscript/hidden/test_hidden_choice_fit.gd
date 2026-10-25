extends GutTest
## Hidden check for the beta's fix-bug: every choice, in every language, fits its button in at most two lines (the
## choice buttons' font at 22 px, 440 px of text in a 460 px column), and the French answers are still French.

const FONT_SIZE := 22
const WIDTH := 440.0

var graph := StoryGraph.from_files()


func after_each():
	TranslationServer.set_locale("en")


func _lines(text: String) -> int:
	var font := ThemeDB.fallback_font
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, WIDTH, FONT_SIZE, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	return roundi(size.y / font.get_height(FONT_SIZE))


func test_hidden_every_choice_fits_in_two_lines():
	for locale in TranslationServer.get_loaded_locales():
		TranslationServer.set_locale(locale)
		for id: String in graph.choices:
			var text := tr(graph.choices[id].text)
			assert_lte(_lines(text), 2, "%s in %s: %s" % [id, locale, text])


func test_hidden_the_toll_answers_are_still_french():
	for id in ["toll_true", "toll_lie"]:
		var key: String = graph.choice(id).text
		TranslationServer.set_locale("en")
		var english := tr(key)
		TranslationServer.set_locale("fr")
		var french := tr(key)
		assert_ne(french, key, id)
		assert_ne(french, english, id)
		assert_gt(french.length(), 10, id)
