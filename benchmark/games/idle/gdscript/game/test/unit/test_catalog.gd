extends GutTest
## Catalog: the data the economy runs on, and the balance it promises.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_producers_come_in_price_order():
	assert_gte(catalog.producers.size(), 3)
	for i in range(1, catalog.producers.size()):
		assert_gt(float(catalog.producers[i].cost), float(catalog.producers[i - 1].cost))


func test_each_later_producer_takes_longer_to_pay_back():
	var last := 0.0
	for p: Dictionary in catalog.producers:
		var payback := float(p.cost) / float(p.rate)
		assert_gt(payback, last, str(p.id))
		last = payback


func test_every_upgrade_targets_something_that_exists():
	for u: Dictionary in catalog.upgrades:
		var target := str(u.target)
		assert_true(target == "all" or target == "tap" or not catalog.producer(target).is_empty(), str(u.id))


func test_the_economy_settings_are_there():
	for id in ["tap", "milestone_every", "milestone_multiplier", "dawn_base", "ember_bonus", "offline_cap_seconds", "autosave_seconds"]:
		assert_gt(catalog.setting(id), 0.0, id)
