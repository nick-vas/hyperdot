extends GutTest
## Hidden check for the alpha's add-content: the Star Loom, its upgrade, its name and its place in the balance.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_the_star_loom_comes_after_the_moon_lily():
	var ids := catalog.producers.map(func(p: Dictionary) -> String: return str(p.id))
	assert_true(ids.has("star_loom"))
	assert_eq(ids.find("star_loom"), ids.find("moon_lily") + 1)
	var p := catalog.producer("star_loom")
	assert_eq(str(p.name), "PRODUCER_STAR_LOOM")
	assert_between(float(p.cost), 200000.0, 500000.0)
	assert_between(float(p.growth), 1.10, 1.15)


func test_hidden_it_pays_back_slower_than_the_lily_but_not_twice_as_slow():
	var lily := catalog.producer("moon_lily")
	var loom := catalog.producer("star_loom")
	var lily_payback := float(lily.cost) / float(lily.rate)
	var loom_payback := float(loom.cost) / float(loom.rate)
	assert_gt(loom_payback, lily_payback)
	assert_lt(loom_payback, 2.0 * lily_payback)


func test_hidden_star_thread_doubles_it_at_ten():
	var u := catalog.upgrade("star_thread")
	assert_false(u.is_empty())
	assert_eq(str(u.name), "UPGRADE_STAR_THREAD")
	assert_eq(str(u.target), "star_loom")
	assert_eq(float(u.multiplier), 2.0)
	assert_eq(int(u.needs), 10)
	assert_between(float(u.cost), 2e6, 1e7)
	var economy := Economy.new(catalog)
	economy.owned["star_loom"] = 10
	economy.glow = float(u.cost)
	var before := economy.producer_rate("star_loom")
	assert_true(economy.buy_upgrade("star_thread"))
	assert_almost_eq(economy.producer_rate("star_loom"), before * 2.0, before * 1e-9)


func test_hidden_its_names_are_translated():
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate("PRODUCER_STAR_LOOM"), "Star Loom")
	assert_eq(TranslationServer.translate("UPGRADE_STAR_THREAD"), "Star Thread")
