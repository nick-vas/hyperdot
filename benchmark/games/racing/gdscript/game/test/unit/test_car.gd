extends GutTest
## Car: throttle and top speed, braking and reverse, steering that needs speed, the grass, and the same handling at any
## tick rate.

const DT := 1.0 / 60.0


func _drive(car: Car, throttle: float, steer: float, seconds: float, rate := 60, road := true) -> void:
	for i in roundi(seconds * rate):
		car.step(throttle, steer, 1.0 / rate, road)


func test_full_throttle_speeds_the_car_up_along_its_heading():
	var car := Car.new()
	car.heading = PI / 2.0
	_drive(car, 1.0, 0.0, 1.0)
	assert_gt(car.speed, 400.0)
	assert_almost_eq(car.position.x, 0.0, 0.01)
	assert_gt(car.position.y, 200.0)


func test_top_speed_is_acceleration_over_drag():
	var car := Car.new()
	_drive(car, 1.0, 0.0, 12.0)
	assert_almost_eq(car.speed, Car.ACCEL / Car.DRAG, 15.0)


func test_half_throttle_tops_out_at_half_the_speed():
	var car := Car.new()
	_drive(car, 0.5, 0.0, 12.0)
	assert_almost_eq(car.speed, Car.ACCEL / Car.DRAG / 2.0, 10.0)


func test_coasting_slows_the_car_down():
	var car := Car.new()
	car.speed = 500.0
	_drive(car, 0.0, 0.0, 1.0)
	# About DRAG of the speed goes each second: 500 px/s coasts down to about 225 in one.
	assert_between(car.speed, 200.0, 250.0)


func test_braking_stops_the_car_without_reversing_in_the_same_tick():
	var car := Car.new()
	car.speed = 100.0
	var ticks := 0
	while car.speed > 0.0 and ticks < 60:
		car.step(-1.0, 0.0, DT)
		ticks += 1
		assert_true(car.speed >= 0.0, "never below zero while braking from forward")
	assert_eq(car.speed, 0.0)
	assert_lt(ticks, 10, "a tenth of a second from 100 px/s")


func test_holding_the_brake_once_stopped_reverses_up_to_the_limit():
	var car := Car.new()
	_drive(car, -1.0, 0.0, 5.0)
	assert_almost_eq(car.speed, -Car.REVERSE_MAX, 0.01)


func test_a_standing_car_does_not_turn():
	var car := Car.new()
	_drive(car, 0.0, 1.0, 1.0)
	assert_eq(car.heading, 0.0)


func test_a_slow_car_turns_less_than_a_quick_one():
	var car := Car.new()
	car.speed = Car.TURN_SPEED / 4.0
	car.step(0.0, 1.0, DT)
	assert_almost_eq(car.heading, Car.TURN_RATE / 4.0 * DT, 0.0005)


func test_steering_right_turns_clockwise_on_screen():
	var car := Car.new()
	car.speed = 300.0
	_drive(car, 0.0, 1.0, 0.25)
	assert_gt(car.heading, 0.3)


func test_reversing_turns_the_nose_the_other_way():
	var car := Car.new()
	car.speed = -150.0
	_drive(car, 0.0, 1.0, 0.25)
	assert_lt(car.heading, -0.1)


func test_grip_limits_the_turn_at_speed():
	var slow := Car.new()
	slow.speed = 200.0
	var fast := Car.new()
	fast.speed = 700.0
	slow.step(0.0, 1.0, DT)
	fast.step(0.0, 1.0, DT)
	assert_almost_eq(slow.heading, Car.TURN_RATE * DT, 0.0001)
	assert_lt(fast.heading, slow.heading, "full lock at 700 px/s turns less than at 200")


func test_the_grass_holds_the_car_back():
	var road := Car.new()
	var grass := Car.new()
	_drive(road, 1.0, 0.0, 6.0)
	_drive(grass, 1.0, 0.0, 6.0, 60, false)
	assert_almost_eq(grass.speed, Car.ACCEL / Car.GRASS_DRAG, 10.0)
	assert_lt(grass.speed, road.speed / 2.0)


func test_a_straight_run_is_the_same_at_30_and_120_ticks():
	var slow := Car.new()
	var fast := Car.new()
	_drive(slow, 1.0, 0.0, 4.0, 30)
	_drive(fast, 1.0, 0.0, 4.0, 120)
	assert_almost_eq(slow.speed, fast.speed, fast.speed * 0.02)
	assert_almost_eq(slow.position.x, fast.position.x, fast.position.x * 0.02)
