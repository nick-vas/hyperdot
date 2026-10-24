extends GutTest
## Every line, choice and ending title of the story has its text in every language the game ships: a key missing from
## the tables would be shown to the player as it is.

var graph := StoryGraph.from_files()


func after_each():
	TranslationServer.set_locale("en")


func _keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for id: String in graph.nodes:
		keys.append(graph.nodes[id].text)
	for id: String in graph.choices:
		if not keys.has(graph.choices[id].text):
			keys.append(graph.choices[id].text)
	for id in graph.ending_ids:
		keys.append(graph.endings[id].title)
	for key in ["SPEAKER_NARRATOR", "SPEAKER_STRANGER", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3"]:
		keys.append(key)
	return keys


func test_every_story_text_is_translated_in_every_language():
	for locale in TranslationServer.get_loaded_locales():
		TranslationServer.set_locale(locale)
		for key in _keys():
			assert_ne(TranslationServer.translate(key), key, "%s in %s" % [key, locale])
