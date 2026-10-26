extends GutTest
## Bot: the --autoplay player's choices.

var economy: Economy


func before_each():
	economy = Economy.new(Catalog.from_files())


func test_with_nothing_it_gathers():
	assert_eq(Bot.next_action(economy).kind, "gather")


func test_it_buys_what_pays_back_soonest():
	economy.glow = 200.0
	var action := Bot.next_action(economy)
	assert_eq(action.kind, "buy")
	assert_eq(action.id, "wick_moth")


func test_it_takes_an_upgrade_it_can_pay_for():
	economy.owned["wick_moth"] = 10
	economy.glow = 160.0
	assert_eq(Bot.next_action(economy), {"kind": "upgrade", "id": "twin_wicks"})


func test_it_dawns_once_the_dawn_doubles_its_embers():
	economy.embers = 3.0
	economy.earn(9e6)
	assert_eq(Bot.next_action(economy).kind, "dawn")
	economy.embers = 4.0
	assert_ne(Bot.next_action(economy).kind, "dawn")
