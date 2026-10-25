extends GutTest
## Main: the save read at start and the time away paid, and the save written again.

const PATH := "user://test_main.json"

var now := 1761000000.0


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _start() -> Control:
	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = PATH
	main.clock = func() -> float: return now
	add_child_autofree(main)
	await wait_physics_frames(1)
	return main


func _write(economy: Dictionary, saved_at: float) -> void:
	SaveStore.new(PATH).write({"economy": economy, "saved_at": saved_at, "settings": {"volume": 1.0, "locale": "en"}})


func test_a_first_start_is_a_new_hive():
	var main := await _start()
	assert_eq(main.game.economy.glow, 0.0)
	assert_false(main.get_node("Game/WelcomePanel").visible)


func test_time_away_is_paid_and_shown():
	_write({"glow": 10.0, "owned": {"glow_snail": 5}}, now - 3600.0)
	var main := await _start()
	assert_almost_eq(main.game.economy.glow, 10.0 + 3600.0 * 20.0, 1.0)
	assert_true(main.get_node("Game/WelcomePanel").visible)


func test_the_save_keeps_the_game_and_the_time():
	var main := await _start()
	main.game.add_glow(500.0)
	now += 60.0
	assert_true(main.save_now())
	var data := SaveStore.new(PATH).read()
	assert_eq(float(data.economy.glow), main.game.economy.glow)
	assert_eq(data.saved_at, now)


func test_a_dawn_is_saved_at_once():
	var main := await _start()
	main.game.add_glow(1e6)
	main.game.economy.dawn()
	var data := SaveStore.new(PATH).read()
	assert_eq(float(data.economy.prestige.embers), 1.0)
