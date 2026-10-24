extends GutTest
## The data's meaning, past what data.json checks: upgrades that make towers better for more sap, maps with a way
## through, and waves numbered in order.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_every_tower_has_two_upgrades_each_better_and_dearer():
	for id in catalog.tower_ids:
		assert_eq(catalog.max_level(id), 3, id)
		var last := catalog.stats(id, 1)
		for level in [2, 3]:
			var now := catalog.stats(id, level)
			assert_gt(int(now.damage), int(last.damage), "%s level %d hits harder" % [id, level])
			assert_true(float(now["range"]) >= float(last["range"]), "%s level %d reaches as far" % [id, level])
			assert_true(int(now.reload) <= int(last.reload), "%s level %d fires as often" % [id, level])
			last = now
		assert_gt(catalog.upgrade_cost(id, 3), catalog.upgrade_cost(id, 2), id)


func test_every_map_has_one_gate_one_store_and_a_way_between():
	for row in catalog.maps:
		var gates := 0
		var stores := 0
		for line: String in row.rows:
			assert_eq(line.length(), 16, row.id)
			gates += line.count("S")
			stores += line.count("G")
		assert_eq(gates, 1, row.id)
		assert_eq(stores, 1, row.id)
		assert_false(PathMap.from_rows(row.rows).route.is_empty(), row.id)


func test_waves_are_numbered_from_one_and_send_known_pests():
	for row in catalog.maps:
		var waves := catalog.waves_for(row.id)
		assert_gt(waves.size(), 0, row.id)
		for i in waves.size():
			assert_eq(int(waves[i].number), i + 1, row.id)
			assert_gt(waves[i].groups.size(), 0, "%s wave %d" % [row.id, i + 1])
			for group: Dictionary in waves[i].groups:
				assert_true(catalog.enemies.has(group.enemy), group.enemy)


func test_the_maps_come_in_campaign_order():
	assert_eq(catalog.map_at(1).id, "meadow")
	for i in range(1, catalog.map_count()):
		assert_lt(int(catalog.map_at(i).order), int(catalog.map_at(i + 1).order))
