extends GutTest
## Hidden check for the alpha's fix-bug: the chase camera eases the same at any frame rate, never jumps past where it
## is heading when a frame takes long, still eases (it is not bolted to the car), looks ahead, and keeps the car on the
## screen through a hairpin taken flat out with hitches.

const JUMP := Vector2(300, 0)


func _camera() -> ChaseCamera:
	var camera := ChaseCamera.new()
	camera.zoom = Vector2(0.8, 0.8)
	add_child_autofree(camera)
	camera.reset_to(Vector2.ZERO)
	return camera


## How far the view still is from a car that jumped 300 px and then stood still, after the given seconds at an fps.
func _left_after(fps: int, seconds: float) -> float:
	var camera := _camera()
	for i in roundi(seconds * fps):
		camera.follow(JUMP, Vector2.ZERO, 1.0 / fps)
	return camera.focus.distance_to(JUMP)


func test_hidden_the_view_eases_the_same_at_any_frame_rate():
	for seconds in [0.5, 1.0]:
		var at_60 := _left_after(60, seconds)
		assert_gt(at_60, 0.5, "still easing after %.1f s" % seconds)
		for fps in [30, 144]:
			assert_almost_eq(_left_after(fps, seconds), at_60, 0.5, "%d fps against 60 after %.1f s" % [fps, seconds])


func test_hidden_a_long_frame_never_overshoots():
	for frame in [0.1, 0.25, 0.5]:
		var camera := _camera()
		var before := camera.focus
		camera.follow(JUMP, Vector2.ZERO, frame)
		var moved := camera.focus - before
		assert_gt(moved.x, 0.0, "a %.2f s frame moves towards the car" % frame)
		assert_lt(moved.x, JUMP.x, "a %.2f s frame stops short of the car" % frame)
		assert_almost_eq(moved.y, 0.0, 0.001)


func test_hidden_the_view_is_not_bolted_to_the_car():
	var camera := _camera()
	camera.follow(JUMP, Vector2.ZERO, 1.0 / 60.0)
	assert_lt(camera.focus.x, JUMP.x / 2.0, "one frame covers less than half the jump")


func test_hidden_the_view_looks_ahead_at_speed():
	var camera := _camera()
	var car := Vector2.ZERO
	for i in 120:
		car += Vector2(0, -700) / 60.0
		camera.follow(car, Vector2(0, -700), 1.0 / 60.0)
	assert_lt(camera.focus.y, car.y - 40.0, "the view is ahead of a car going up")


func test_hidden_a_hairpin_flat_out_keeps_the_car_on_screen():
	for fps in [20, 60, 144]:
		var camera := _camera()
		var half := Vector2(1280, 720) / camera.zoom / 2.0 - Vector2(40, 40)
		var car := Vector2.ZERO
		var t := 0.0
		var frame := 0
		while t < 4.0:
			# Every twentieth frame is a hitch of a sixth of a second.
			var dt := 1.0 / fps if frame % 20 != 19 else 1.0 / 6.0
			frame += 1
			t += dt
			var velocity := Vector2(0, -800) if t < 1.0 else Vector2(0, 800)
			car += velocity * dt
			camera.follow(car, velocity, dt)
			var off := (car - camera.focus).abs()
			assert_true(off.x <= half.x and off.y <= half.y, "%d fps, %.2f s: the car is %s from the middle" % [fps, t, off])
			if off.x > half.x or off.y > half.y:
				return
