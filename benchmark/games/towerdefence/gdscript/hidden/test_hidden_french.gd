extends GutTest
## Hidden acceptance for the alpha-to-beta milestone: the game ships in French, menus, maps and towers included.


func after_each():
	TranslationServer.set_locale("en")


func test_hidden_french_is_loaded():
	assert_has(Array(TranslationServer.get_loaded_locales()), "fr")


func test_hidden_menu_maps_and_towers_are_translated():
	var catalog := Catalog.from_files()
	var keys := ["MENU_START", str(catalog.map_at(3).name)]
	for id in catalog.tower_ids:
		keys.append(str(catalog.towers[id].name))
	for key: String in keys:
		TranslationServer.set_locale("en")
		var english := TranslationServer.translate(key)
		TranslationServer.set_locale("fr")
		var french := TranslationServer.translate(key)
		assert_ne(french, key, key)
		assert_ne(french, english, key)
