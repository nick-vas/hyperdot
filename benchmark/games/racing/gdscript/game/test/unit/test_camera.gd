extends GutTest
## ChaseCamera: it starts on the car, catches up with it, and looks ahead the way the car goes.

var camera: ChaseCamera


func before_each():
	camera = ChaseCamera.new()
	add_child_autofree(camera)
	camera.reset_to(Vector2(100, 50))


func test_a_reset_centres_the_view_on_the_car():
	assert_eq(camera.focus, Vector2(100, 50))
	assert_eq(camera.position, Vector2(100, 50))


func test_the_view_catches_up_with_a_car_that_stopped_elsewhere():
	for i in 120:
		camera.follow(Vector2(300, 50), Vector2.ZERO, 1.0 / 60.0)
	assert_almost_eq(camera.focus.distance_to(Vector2(300, 50)), 0.0, 1.0)


func test_the_view_looks_ahead_of_a_moving_car():
	var car := Vector2(100, 50)
	for i in 180:
		car += Vector2(400, 0) / 60.0
		camera.follow(car, Vector2(400, 0), 1.0 / 60.0)
	assert_gt(camera.focus.x, car.x + 30.0, "ahead of the car")
	assert_almost_eq(camera.focus.y, car.y, 1.0)
