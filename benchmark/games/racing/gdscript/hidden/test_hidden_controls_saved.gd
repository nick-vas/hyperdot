extends GutTest
## Hidden check for the beta's fix-flow: keys rebound in Settings survive a restart. Saved by SaveStore, read back by a
## new game and applied the way Main applies them at start, the key drives its action and the gamepad still does.

const PATH := "user://hidden_controls_save.json"
const MAIN := preload("res://ui/main.gd")


func after_each():
	Controls.reset()
	for path in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _has_joypad(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func test_hidden_a_rebound_key_survives_a_restart():
	var save := SaveStore.defaults()
	Controls.rebind("accelerate", KEY_I)
	Controls.rebind("steer_left", KEY_J)
	save.controls = Controls.to_dict()
	assert_true(SaveStore.new(PATH).write(save))
	# The game quits: the bindings go back to the project's.
	Controls.reset()
	assert_eq(Controls.key_of("accelerate"), KEY_W)
	MAIN.apply_settings(SaveStore.new(PATH).read())
	assert_eq(Controls.key_of("accelerate"), KEY_I)
	assert_eq(Controls.key_of("steer_left"), KEY_J)
	assert_eq(Controls.key_of("brake"), KEY_S, "keys not rebound stay")
	assert_true(_has_joypad("accelerate"))


func test_hidden_the_other_settings_still_survive():
	var save := SaveStore.defaults()
	save.settings.locale = "fr"
	save.best["1"] = 27000
	Controls.rebind("brake", KEY_K)
	save.controls = Controls.to_dict()
	SaveStore.new(PATH).write(save)
	var back := SaveStore.new(PATH).read()
	assert_eq(back.settings.locale, "fr")
	assert_eq(int(back.best["1"]), 27000)
	assert_eq(back.controls.get("brake"), "K")
	TranslationServer.set_locale("en")
