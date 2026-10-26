extends GutTest
## Meta: embers banked across runs, vigor bought with them, the deepest floor and the runs counted.


func test_a_won_run_banks_every_ember():
	var save := SaveStore.defaults()
	Meta.bank(save, 7, 4, true)
	assert_eq(int(save.meta.embers), 7)
	assert_eq(int(save.meta.best_floor), 4)
	assert_eq(int(save.meta.runs), 1)


func test_a_death_banks_half_the_embers():
	var save := SaveStore.defaults()
	Meta.bank(save, 7, 2, false)
	assert_eq(int(save.meta.embers), 3)


func test_vigor_costs_embers_and_adds_hp():
	var save := SaveStore.defaults()
	save.meta.embers = 16
	assert_eq(Meta.max_hp(save), Meta.BASE_HP)
	assert_true(Meta.buy_vigor(save))
	assert_eq(int(save.meta.embers), 11)
	assert_true(Meta.buy_vigor(save))
	assert_eq(int(save.meta.embers), 1)
	assert_false(Meta.buy_vigor(save), "15 embers for the third level")
	assert_eq(int(save.meta.vigor), 2)
	assert_eq(Meta.max_hp(save), Meta.BASE_HP + 2)


func test_vigor_stops_at_its_top_level():
	var save := SaveStore.defaults()
	save.meta.embers = 100
	for i in 5:
		Meta.buy_vigor(save)
	assert_eq(int(save.meta.vigor), Meta.VIGOR_MAX)
	assert_eq(int(save.meta.embers), 100 - 5 - 10 - 15)
