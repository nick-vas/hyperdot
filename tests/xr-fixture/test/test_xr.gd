# What the godot-xr skill claims, held where it can be held without a headset (tests/Test-Xr.ps1 runs it with GUT):
#   - every XR name the skill quotes exists in the engine's ClassDB (api.txt, written from the skill by the script)
#   - a scene with an XR origin loads and runs its logic with no XR interface
#   - a tracker added to the XRServer drives an XRController3D: its pose, its velocity, its hand
#   - the numbers of xr_math.gd: the peak of the last frames for a throw, snap turns, the origin turning about the player,
#     the vignette, the one-controller choice
# What needs a headset (tracking quality, passthrough, how comfortable any of it feels) is not here.
extends GutTest

const XrMath := preload("res://xr_math.gd")
const Scene := preload("res://xr_game.tscn")


# --- The names the skill quotes -------------------------------------------------------------------------------------

func _kind(cls: String, member: String) -> String:
	for p in ClassDB.class_get_property_list(cls, false):
		if p.name == member:
			return "property"
	if ClassDB.class_has_method(cls, member, false):
		return "method"
	if ClassDB.class_has_signal(cls, member):
		return "signal"
	var c := cls
	while c != "":
		if ClassDB.class_has_integer_constant(c, member):
			return "constant"
		if ClassDB.class_has_enum(c, member, true):
			return "enum"
		c = ClassDB.get_parent_class(c)
	return ""


func test_every_name_the_skill_quotes_exists() -> void:
	var file := FileAccess.open("res://test/api.txt", FileAccess.READ)
	assert_not_null(file, "api.txt was not written by the script")
	if file == null:
		return
	var checked := 0
	var missing: Array[String] = []
	for line in file.get_as_text().split("\n", false):
		var token := line.strip_edges()
		if token.begins_with("xr/"):
			if not ProjectSettings.has_setting(token):
				missing.append(token)
		else:
			var parts := token.trim_suffix("()").split(".")
			if not ClassDB.class_exists(parts[0]):
				missing.append(token + " (no such class)")
			elif parts.size() > 1 and _kind(parts[0], parts[1]) == "":
				missing.append(token)
		checked += 1
	gut.p("%d names checked" % checked)
	assert_gt(checked, 40, "the skill quotes fewer names than expected")
	assert_eq(missing, [] as Array[String], "names the engine does not have")


func test_class_tree_is_as_the_skill_says() -> void:
	assert_eq(ClassDB.get_parent_class("XROrigin3D"), "Node3D")
	assert_eq(ClassDB.get_parent_class("XRCamera3D"), "Camera3D")
	assert_eq(ClassDB.get_parent_class("XRNode3D"), "Node3D")
	assert_eq(ClassDB.get_parent_class("XRController3D"), "XRNode3D")
	assert_eq(ClassDB.get_parent_class("OpenXRInterface"), "XRInterface")
	assert_eq(ClassDB.get_parent_class("XRHandModifier3D"), "SkeletonModifier3D")
	assert_eq(ClassDB.get_parent_class("XRHandTracker"), "XRPositionalTracker")


func test_tracker_names_and_hands() -> void:
	var left := XRController3D.new()
	left.tracker = &"left_hand"
	assert_eq(left.tracker, &"left_hand")
	assert_eq(XRPositionalTracker.TRACKER_HAND_LEFT, 1)
	assert_eq(XRPositionalTracker.TRACKER_HAND_RIGHT, 2)
	left.free()


# --- No runtime ------------------------------------------------------------------------------------------------------

func test_no_interface_without_a_runtime() -> void:
	assert_null(XRServer.primary_interface, "no primary interface without a runtime")
	assert_eq(XRServer.world_scale, 1.0)
	var openxr := XRServer.find_interface("OpenXR")
	assert_not_null(openxr, "the OpenXR module registers its interface even with no headset")
	if openxr:
		assert_false(openxr.is_initialized(), "registered is not initialized (setup_xr: 'A registered interface means nothing more than that the interface is available')")
	assert_null(XRServer.find_interface("NoSuchInterface"))


func test_scene_runs_with_no_interface() -> void:
	var rig: XROrigin3D = Scene.instantiate()
	add_child_autofree(rig)
	await get_tree().process_frame
	assert_eq(rig.mode, rig.Mode.FLAT)
	assert_false(rig.start(), "start() reports that there is no headset")
	assert_false(get_viewport().use_xr, "the viewport stays on the screen")
	for hand in [&"left_hand", &"right_hand"]:
		var c: XRController3D = rig.controller(hand)
		assert_not_null(c, "a controller for " + String(hand))
		assert_false(c.get_is_active())
		assert_false(c.get_has_tracking_data())
		assert_false(c.is_button_pressed(&"trigger_click"), "polling a button with no runtime is false, not an error")
		assert_eq(c.get_float(&"trigger"), 0.0)
		assert_eq(c.get_vector2(&"primary"), Vector2.ZERO)
	assert_eq(rig.active_hand(), &"", "no controller, no active hand")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(rig.release_velocity(&"right_hand"), Vector3.ZERO, "a throw with nothing tracked has no speed")
	assert_true(rig.world_scale > 0.0)


func test_origin_world_scale_reaches_the_server() -> void:
	var rig: XROrigin3D = Scene.instantiate()
	add_child_autofree(rig)
	await get_tree().process_frame
	rig.world_scale = 2.0
	assert_eq(XRServer.world_scale, 2.0, "the current origin sets the server's world scale")
	rig.world_scale = 1.0
	assert_eq(XRServer.world_scale, 1.0)


# --- A tracker stands in for a controller ----------------------------------------------------------------------------

func _add_tracker(tracker_name: StringName, hand: int) -> XRPositionalTracker:
	var t := XRPositionalTracker.new()
	t.type = XRServer.TRACKER_CONTROLLER
	t.name = tracker_name
	t.hand = hand
	XRServer.add_tracker(t)
	return t


func test_a_tracker_drives_a_controller() -> void:
	var rig: XROrigin3D = Scene.instantiate()
	add_child_autofree(rig)
	await get_tree().process_frame
	var tracker := _add_tracker(&"right_hand", XRPositionalTracker.TRACKER_HAND_RIGHT)
	await get_tree().process_frame
	var right: XRController3D = rig.controller(&"right_hand")
	assert_eq(right.get_tracker_hand(), XRPositionalTracker.TRACKER_HAND_RIGHT)
	tracker.set_pose(&"default", Transform3D(Basis.IDENTITY, Vector3(0.3, 1.2, -0.4)), Vector3(0, 0, -4), Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await get_tree().process_frame
	assert_true(right.get_has_tracking_data())
	assert_true(right.get_is_active())
	assert_almost_eq(right.position, Vector3(0.3, 1.2, -0.4), Vector3.ONE * 0.001, "the controller moves to its pose, in the origin's space")
	assert_eq(right.get_pose().linear_velocity, Vector3(0, 0, -4), "XRNode3D.get_pose() carries the velocity")
	assert_eq(rig.active_hand(), &"right_hand", "one tracked controller is the active hand")
	assert_false(rig.controller(&"left_hand").get_has_tracking_data())
	# The rig records the velocity each physics frame; a throw leaves with the origin's orientation applied.
	rig.rotate_y(PI / 2.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(rig.release_velocity(&"right_hand"), Vector3(-4, 0, 0), Vector3.ONE * 0.001, "-Z in tracking space is -X in a world turned a quarter left")
	assert_eq(rig.release_velocity(&"right_hand"), Vector3.ZERO, "the samples are used up by the release")
	# Losing tracking forgets the samples.
	rig.record_sample(&"right_hand", Vector3(9, 0, 0))
	tracker.invalidate_pose(&"default")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(right.get_has_tracking_data())
	assert_eq(rig.release_velocity(&"right_hand"), Vector3.ZERO, "a hand that was lost throws nothing")
	XRServer.remove_tracker(tracker)


func test_velocity_from_positions_when_the_pose_has_none() -> void:
	var rig: XROrigin3D = Scene.instantiate()
	add_child_autofree(rig)
	await get_tree().process_frame
	var tracker := _add_tracker(&"left_hand", XRPositionalTracker.TRACKER_HAND_LEFT)
	await get_tree().process_frame
	tracker.set_pose(&"default", Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await get_tree().physics_frame
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in range(1, 5):
		tracker.set_pose(&"default", Transform3D(Basis.IDENTITY, Vector3(i * 0.1, 0, 0)), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await get_tree().physics_frame
	var v: Vector3 = rig.release_velocity(&"left_hand")
	assert_gt(v.x, 0.0, "positions that move +X give a +X velocity (%s)" % v)
	assert_almost_eq(v.y, 0.0, 0.001)
	XRServer.remove_tracker(tracker)


# --- xr_math.gd -------------------------------------------------------------------------------------------------------

func test_throw_takes_the_peak_not_the_release_frame() -> void:
	var samples: Array = []
	# a flick: speeds 1, 2, 5, 3, 1 m/s, the hand slowing before the button opens
	for s in [1.0, 2.0, 5.0, 3.0, 1.0]:
		samples.append(Vector3(0, 0, -s))
	assert_eq(XrMath.peak_velocity(samples), Vector3(0, 0, -5), "the peak, not the last (-1) and not the mean (-2.4)")
	assert_eq(XrMath.peak_velocity([]), Vector3.ZERO)
	assert_eq(XrMath.peak_velocity([Vector3(1, 2, 3)]), Vector3(1, 2, 3))


func test_throw_window_is_the_last_ten_frames() -> void:
	var samples: Array = [Vector3(0, 0, -50)]   # a fast swing 11 frames ago
	for i in 10:
		samples.append(Vector3(0, 0, -2))
	assert_eq(XrMath.peak_velocity(samples), Vector3(0, 0, -2), "the swing is outside the window")
	samples.append(Vector3(0, 0, -2))
	assert_eq(XrMath.peak_velocity(samples, 12), Vector3(0, 0, -50), "a wider window sees it")
	assert_eq(XrMath.THROW_WINDOW, 10)


func test_peak_keeps_the_direction_of_the_peak_frame() -> void:
	var samples: Array = [Vector3(3, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, -1)]
	assert_eq(XrMath.peak_velocity(samples), Vector3(0, 4, 0))


func test_velocity_from_positions() -> void:
	assert_eq(XrMath.velocity_from_positions(Vector3.ZERO, Vector3(0.1, 0, 0), 0.01), Vector3(10, 0, 0))
	assert_eq(XrMath.velocity_from_positions(Vector3.ZERO, Vector3.ONE, 0.0), Vector3.ZERO)


func test_world_velocity() -> void:
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(5, 0, 5))
	assert_almost_eq(XrMath.world_velocity(turned, Vector3(0, 0, -1)), Vector3(-1, 0, 0), Vector3.ONE * 0.0001)
	assert_almost_eq(XrMath.world_velocity(turned, Vector3(0, 0, -1), Vector3(0, 0, 3)), Vector3(-1, 0, 3), Vector3.ONE * 0.0001, "a vehicle's speed is added")


func test_body_is_under_the_head_not_at_the_origin() -> void:
	var origin := Transform3D(Basis(Vector3.UP, PI), Vector3(10, 0.5, 0))
	var body := XrMath.body_position(origin, Vector3(1.0, 1.7, 0.0))
	assert_almost_eq(body, Vector3(9, 0.5, 0), Vector3.ONE * 0.0001, "1 m to the origin's +X is 1 m to the world's -X when the origin is turned half a circle; height is the floor's")


func test_turning_the_origin_about_the_body_leaves_the_body_where_it_is() -> void:
	var origin := Transform3D(Basis.IDENTITY, Vector3(2, 0, 3))
	var head := Vector3(1.5, 1.7, -0.8)   # the player stands 1.5 m from the middle of the room
	var before := XrMath.body_position(origin, head)
	var turned := XrMath.rotate_origin_about(origin, before, deg_to_rad(30.0))
	assert_almost_eq(XrMath.body_position(turned, head), before, Vector3.ONE * 0.0001, "the body stays")
	# The naive way, turning the origin about itself, moves the player around the room.
	var naive := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)) * origin.basis, origin.origin)
	assert_gt(XrMath.body_position(naive, head).distance_to(before), 0.5, "turning about the origin swings the player")
	# The head looks 30 degrees the other way round afterwards.
	var forward := turned.basis * Vector3(0, 0, -1)
	assert_almost_eq(forward.angle_to(Vector3(0, 0, -1)), deg_to_rad(30.0), 0.0001)


func test_blackout_grows_with_the_gap_and_is_clamped() -> void:
	assert_eq(XrMath.blackout(0.0), 0.0)
	assert_eq(XrMath.blackout(0.03), 0.0, "a few centimetres of gap are free")
	assert_eq(XrMath.blackout(0.15), 1.0)
	assert_eq(XrMath.blackout(2.0), 1.0, "never past black")
	var last := 0.0
	for i in range(1, 100):
		var b := XrMath.blackout(i * 0.002)
		assert_true(b >= last, "never gets lighter as the gap grows")
		last = b
	assert_almost_eq(XrMath.blackout(0.09), 0.5, 0.0001)


func test_twelve_snap_turns_are_a_full_circle() -> void:
	var turn := XrMath.SnapTurn.new()
	var total := 0.0
	for i in 12:
		total += turn.update(1.0)
		turn.update(0.0)
	assert_almost_eq(total, -360.0, 0.0001, "30 degrees each, clockwise for a push right")
	assert_eq(XrMath.SnapTurn.new().update(-1.0), 30.0, "a push left turns left")


func test_a_held_stick_turns_once() -> void:
	var turn := XrMath.SnapTurn.new()
	var total := 0.0
	for i in 120:
		total += turn.update(1.0)
	assert_eq(total, -30.0, "one push, one turn, however long it is held")
	assert_eq(turn.update(0.5), 0.0, "between release and press it stays disarmed")
	turn.update(0.2)
	assert_eq(turn.update(0.9), -30.0, "back under release, armed again")


func test_stick_noise_never_turns() -> void:
	var turn := XrMath.SnapTurn.new()
	for x in [0.0, 0.1, -0.3, 0.5, -0.6, 0.69]:
		assert_eq(turn.update(x), 0.0, "stick at %s" % x)


func test_vignette_closes_at_once_and_opens_after_a_rest() -> void:
	var v := XrMath.Vignette.new()
	assert_eq(v.update(0.0, 0.0, 0.016), 1.0)
	assert_almost_eq(v.update(3.0, 0.0, 0.016), 0.35, 0.0001, "full speed closes to the minimum in one frame")
	assert_almost_eq(v.update(0.0, 0.0, 0.25), 0.35, 0.0001, "still closed during the hold")
	assert_almost_eq(v.update(0.0, 0.0, 0.25), 0.35, 0.0001, "still closed at the end of the hold")
	var r := v.update(0.0, 0.0, 0.5)
	assert_gt(r, 0.35)
	assert_lt(r, 1.0)
	for i in 400:
		r = v.update(0.0, 0.0, 0.016)
	assert_eq(r, 1.0, "open again, and never past 1")


func test_vignette_follows_turning_and_half_speed() -> void:
	var v := XrMath.Vignette.new()
	assert_almost_eq(v.update(1.5, 0.0, 0.016), lerpf(1.0, 0.35, 0.5), 0.0001)
	var w := XrMath.Vignette.new()
	assert_almost_eq(w.update(0.0, -90.0, 0.016), 0.35, 0.0001, "turning counts either way")
	assert_almost_eq(w.update(3.0, 0.0, 0.016), 0.35, 0.0001, "an easier push does not open it while moving")
	w.update(0.3, 0.0, 0.016)
	assert_almost_eq(w.radius, 0.35, 0.0001, "slower movement does not open it while the player still moves")


func test_vignette_opens_the_same_at_any_frame_rate() -> void:
	var at60 := XrMath.Vignette.new()
	var at144 := XrMath.Vignette.new()
	at60.update(3.0, 0.0, 0.01)
	at144.update(3.0, 0.0, 0.01)
	for i in 60:   # 1 s at 60 fps
		at60.update(0.0, 0.0, 1.0 / 60.0)
	for i in 144:   # 1 s at 144 fps
		at144.update(0.0, 0.0, 1.0 / 144.0)
	assert_almost_eq(at60.radius, at144.radius, 0.03)
	assert_gt(at60.radius, 0.35)
	assert_lt(at60.radius, 1.0)


func test_one_controller_picks_the_tracked_hand() -> void:
	assert_eq(XrMath.active_hand(true, true), &"right_hand", "both: the preferred one")
	assert_eq(XrMath.active_hand(true, true, &"left_hand"), &"left_hand")
	assert_eq(XrMath.active_hand(true, false), &"left_hand", "only the left is tracked: it does everything")
	assert_eq(XrMath.active_hand(false, true, &"left_hand"), &"right_hand")
	assert_eq(XrMath.active_hand(false, false), &"")
