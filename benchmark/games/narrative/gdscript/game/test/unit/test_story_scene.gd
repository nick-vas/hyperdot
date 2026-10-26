extends GutTest
## The story scene: a line typed out, its choices as buttons, the page turning, the ending panel and the history.

var scene: Control


func before_each():
	scene = load("res://story/story.tscn").instantiate()
	add_child_autofree(scene)
	await wait_physics_frames(2)


func _until_choosing() -> void:
	for i in 300:
		if scene.state == "choosing":
			return
		await wait_physics_frames(1)


func test_the_line_is_typed_out_then_the_choices_appear():
	assert_eq(scene.state, "reading")
	assert_eq(scene.get_node("Choices").get_child_count(), 0)
	await _until_choosing()
	assert_eq(scene.get_node("Panel/Text").visible_characters, -1)
	assert_eq(scene.get_node("Choices").get_child_count(), 2)
	assert_eq(scene.get_node("Choices/Choice0").text, "Good evening. Where are you going?")


func test_a_click_on_the_text_shows_it_whole():
	scene.reveal_all()
	await wait_physics_frames(2)
	assert_eq(scene.state, "choosing")


func test_a_choice_button_turns_the_page_to_its_node():
	await _until_choosing()
	scene.get_node("Choices/Choice1").pressed.emit()
	assert_eq(scene.state, "turning")
	assert_eq(scene.node, "dock", "the page turns first")
	await wait_physics_frames(scene.TURN_TICKS + 2)
	assert_eq(scene.node, "toll")
	assert_eq(scene.story.history, PackedStringArray(["dock_silent"]))


func test_every_line_shown_is_a_checkpoint():
	watch_signals(scene)
	await _until_choosing()
	scene.choose_id("dock_greet")
	await wait_physics_frames(scene.TURN_TICKS + 2)
	assert_signal_emitted(scene, "checkpoint")
	var data: Dictionary = get_signal_parameters(scene, "checkpoint")[0]
	assert_eq(data.node, "toll")
	assert_eq(data.flags.trust, 1)


func test_an_ending_opens_the_ending_panel():
	scene.resume(Story.replay(scene.graph, ["dock_silent", "toll_true", "launch_row", "fog_hurry", "cross_on"]).to_dict())
	await _until_choosing()
	assert_true(scene.choose_id("turn_back"))
	for i in 300:
		if scene.state == "ended":
			break
		await wait_physics_frames(1)
	assert_eq(scene.state, "ended")
	assert_true(scene.get_node("EndingMenu").visible)
	assert_eq(scene.get_node("EndingMenu/Box/Title").text, "The Empty Seat")
	assert_has(scene.found, "return")


func test_the_history_lists_the_lines_and_the_choices():
	await _until_choosing()
	scene.choose_id("dock_silent")
	await wait_physics_frames(scene.TURN_TICKS + 2)
	scene.get_node("HUD/HistoryButton").pressed.emit()
	assert_true(scene.get_node("History").visible)
	var text: String = scene.get_node("History/Box/Scroll/Lines").text
	assert_string_contains(text, "Night on the Hensmouth landing.")
	assert_string_contains(text, "» Nod, and untie the boat.")
	scene.get_node("History/Box/CloseButton").pressed.emit()
	assert_false(scene.get_node("History").visible)
