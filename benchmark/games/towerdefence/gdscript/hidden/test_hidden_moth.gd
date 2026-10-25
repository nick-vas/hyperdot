extends GutTest
## Hidden check for the alpha's add-content: the moth, the Sunken Path's fifth wave, and the map still fair.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_hidden_the_moth_is_the_fastest_pest():
	assert_true(catalog.enemies.has("moth"))
	var moth: Dictionary = catalog.enemies["moth"]
	assert_almost_eq(float(moth.speed), 2.4, 0.001)
	assert_eq(int(moth.hp), 34)
	assert_eq(int(moth.reward), 6)
	assert_eq(int(moth.leak), 1)
	for id in catalog.enemies:
		if id != "moth":
			assert_lt(float(catalog.enemies[id].speed), float(moth.speed), id)
	assert_eq(str(moth.name), "ENEMY_MOTH")
	assert_ne(tr("ENEMY_MOTH"), "ENEMY_MOTH", "named in the translation table")


func test_hidden_the_sunken_path_has_a_fifth_wave_of_moths_and_beetles():
	var waves := catalog.waves_for("sunken")
	assert_eq(waves.size(), 5)
	var fifth: Dictionary = waves[4]
	assert_eq(int(fifth.number), 5)
	assert_eq(int(fifth.bonus), 45)
	var moths := 0
	var beetles := 0
	for group: Dictionary in fifth.groups:
		if group.enemy == "moth":
			moths += int(group.count)
		elif group.enemy == "beetle":
			beetles += int(group.count)
	assert_gte(moths, 12)
	assert_gt(beetles, 0)


func test_hidden_the_sunken_path_stays_fair():
	for seed_value in [1, 2, 3]:
		var battle := Battle.create(catalog, "sunken", seed_value)
		assert_true(Bot.play(battle), "seed %d: lost at wave %d" % [seed_value, battle.wave])
	var idle := Battle.create(catalog, "sunken", 1)
	assert_false(Bot.idle(idle))
