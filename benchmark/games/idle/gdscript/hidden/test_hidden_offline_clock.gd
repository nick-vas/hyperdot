extends GutTest
## Hidden check for the alpha's fix-bug: time away through Main with a clock the test sets. A clock set back pays
## nothing, the time paid is capped, and a clock put right again pays only for the time really away, once.

const PATH := "user://test_hidden_offline_clock.json"
const DAY := 86400.0

var now := 1761000000.0


func after_each():
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## Starts the game as a player opening it at the current clock; production stops after the first tick.
func _open() -> Control:
	var main: Control = load("res://main.tscn").instantiate()
	main.save_path = PATH
	main.clock = func() -> float: return now
	add_child_autofree(main)
	await wait_physics_frames(1)
	main.game.set_physics_process(false)
	return main


func _close(main: Control) -> void:
	main.save_now()
	remove_child(main)
	main.queue_free()


## A hive of 5 glow snails (20 glow a second) saved at the current clock, with no glow.
func _saved_hive() -> void:
	var economy := Economy.new(Catalog.from_files())
	economy.owned["glow_snail"] = 5
	SaveStore.new(PATH).write({"economy": economy.to_dict(), "saved_at": now, "settings": {"volume": 1.0, "locale": "en"}})


func test_hidden_an_hour_away_pays_an_hour():
	_saved_hive()
	now += 3600.0
	var main := await _open()
	assert_almost_eq(main.game.economy.glow, 3600.0 * 20.0, 1.0)
	_close(main)


func test_hidden_a_clock_set_back_pays_nothing():
	_saved_hive()
	now -= DAY
	var main := await _open()
	assert_almost_eq(main.game.economy.glow, 0.0, 1.0)
	assert_false(main.get_node("Game/WelcomePanel").visible)
	_close(main)


func test_hidden_a_month_away_pays_eight_hours():
	_saved_hive()
	now += 30.0 * DAY
	var main := await _open()
	assert_almost_eq(main.game.economy.glow, 28800.0 * 20.0, 1.0)
	_close(main)


func test_hidden_a_clock_put_right_again_pays_only_once():
	_saved_hive()
	var truth := now
	# The clock goes back a day; the player plays for ten minutes and closes the game.
	now = truth - DAY
	var main := await _open()
	now += 600.0
	_close(main)
	# The next morning the clock is right again, an hour after the first save.
	now = truth + 3600.0
	main = await _open()
	assert_almost_eq(main.game.economy.glow, 3600.0 * 20.0, 1.0, "only the hour since the save, not the day the clock was back")
	_close(main)
	# And opening it again a minute later pays a minute, not the night again.
	var glow: float = SaveStore.new(PATH).read().economy.glow
	now += 60.0
	main = await _open()
	assert_almost_eq(main.game.economy.glow - glow, 60.0 * 20.0, 1.0)
	_close(main)
