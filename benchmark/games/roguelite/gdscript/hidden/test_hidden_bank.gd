extends GutTest
## Hidden check for the alpha's fix-bug: what a run brings home joins the embers already banked, after a death as after
## a victory, and survives the save.

const PATH := "user://test_hidden_bank.json"


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_hidden_deaths_and_victories_add_to_the_bank():
	var save := SaveStore.defaults()
	Meta.bank(save, 6, 3, false)
	assert_eq(int(save.meta.embers), 3)
	Meta.bank(save, 5, 1, false)
	assert_eq(int(save.meta.embers), 5)
	Meta.bank(save, 9, 2, true)
	assert_eq(int(save.meta.embers), 14)
	Meta.bank(save, 1, 1, false)
	assert_eq(int(save.meta.embers), 14, "half of one is nothing")
	assert_eq(int(save.meta.best_floor), 3)
	assert_eq(int(save.meta.runs), 4)


func test_hidden_vigor_and_the_bank_survive_runs_and_the_save():
	var store := SaveStore.new(PATH)
	var save := SaveStore.defaults()
	Meta.bank(save, 8, 2, true)
	assert_true(Meta.buy_vigor(save))
	Meta.bank(save, 4, 2, false)
	store.write(save)
	var back := store.read()
	assert_eq(int(back.meta.embers), 5)
	assert_eq(int(back.meta.vigor), 1)
	Meta.bank(back, 10, 4, true)
	assert_eq(int(back.meta.embers), 15)
	assert_true(Meta.buy_vigor(back))
	assert_eq(int(back.meta.embers), 5)
