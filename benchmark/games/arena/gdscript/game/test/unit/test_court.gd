extends GutTest
## The courts in data/: every one loads with four spawns that are clear and out of each other's sight.

func test_the_courts_load_in_order():
	var courts := Court.load_all()
	assert_eq(courts.map(func(c: Court) -> String: return c.id), ["cinder_pit", "hollow_ring"])
	for court in courts:
		assert_eq(court.spawns.size(), ArenaMatch.SLOTS, court.id)
		assert_gt(court.walls.size(), 0, court.id)


func test_every_spawn_is_free_and_sees_no_other():
	for court in Court.load_all():
		for spawn in court.spawns:
			assert_true(court.box_free(spawn.x, spawn.y), "%s %s" % [court.id, spawn])
			for other in court.spawns:
				if other != spawn:
					assert_false(court.clear_line(Vector2(spawn), Vector2(other)), "%s: %s sees %s" % [court.id, spawn, other])


func test_a_clear_line_and_a_blocked_one():
	var court := Court.load_all()[0]
	assert_true(court.clear_line(Vector2(80, 80), Vector2(400, 80)))
	assert_false(court.clear_line(Vector2(400, 80), Vector2(800, 80)), "the top pillar")
