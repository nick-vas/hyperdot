extends GutTest
## Controls: a rebound key replaces the keyboard binding and keeps the gamepad's, and bindings save as key names.


func after_each():
	Controls.reset()


func _has_joypad(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func test_every_action_has_a_key_and_a_gamepad_binding():
	for action in Controls.ACTIONS:
		assert_ne(Controls.key_of(action), KEY_NONE, action)
		assert_true(_has_joypad(action), action)


func test_a_rebound_key_drives_the_action_and_the_gamepad_still_does():
	assert_true(Controls.rebind("accelerate", KEY_J))
	assert_eq(Controls.key_of("accelerate"), KEY_J)
	assert_true(_has_joypad("accelerate"))
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	assert_true(press.is_action("accelerate"))


func test_only_the_game_actions_can_be_rebound():
	assert_false(Controls.rebind("ui_accept", KEY_J))
	assert_false(Controls.rebind("pause", KEY_J))


func test_bindings_save_as_key_names_and_apply_back():
	Controls.rebind("brake", KEY_K)
	var saved := Controls.to_dict()
	assert_eq(saved.brake, "K")
	Controls.reset()
	assert_eq(Controls.key_of("brake"), KEY_S)
	Controls.apply(saved)
	assert_eq(Controls.key_of("brake"), KEY_K)


func test_unknown_actions_and_keys_change_nothing():
	Controls.apply({"jump": "J", "steer_left": "NoSuchKey"})
	assert_eq(Controls.key_of("steer_left"), KEY_A)
	Controls.apply("broken")
	assert_eq(Controls.key_of("steer_left"), KEY_A)
