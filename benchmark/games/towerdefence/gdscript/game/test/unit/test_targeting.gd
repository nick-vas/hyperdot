extends GutTest
## Many pests and towers at once: every pest a tower shoots is in range, and the leading one is shot first.

var catalog: Catalog


func before_each():
	catalog = Catalog.from_files()


func test_every_shot_goes_to_a_pest_in_range():
	var battle := Battle.create(catalog, "meadow", 3)
	battle.gold = 2000
	for cell in [Vector2i(3, 3), Vector2i(6, 5), Vector2i(9, 3), Vector2i(12, 5)]:
		battle.place("thorn", cell)
	var bad := []
	battle.shot_fired.connect(func(cell: Vector2i) -> void:
		var shot: Dictionary = battle.shots[-1]
		var reach := float(catalog.stats(battle.towers[cell].id, 1)["range"])
		if shot.target.pos.distance_to(Enemy.centre(cell)) > reach + 0.001:
			bad.append(cell))
	battle.start_wave()
	for i in 900:
		battle.step()
	assert_gt(battle.kills, 0)
	assert_eq(bad, [])


func test_the_leading_pest_is_shot_first():
	var battle := Battle.custom(catalog, ["S..........G", "............"], 500, 10, [])
	assert_true(battle.place("thorn", Vector2i(5, 1)))
	var pests: Array[Enemy] = []
	for x in [3, 4, 6, 7]:
		var pest := battle.spawn_at("beetle", Vector2i(x, 0))
		pest.speed = 0.0
		pests.append(pest)
	battle.step()
	assert_eq(battle.shots[0].target, pests[3])
