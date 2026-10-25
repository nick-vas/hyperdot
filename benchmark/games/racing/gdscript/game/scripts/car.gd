class_name Car
extends RefCounted
## One car's handling, stepped once a physics tick by Race: throttle and brake along the heading, steering that needs
## speed, drag that is higher off the road. Every rate is per second and every step uses its own dt, so a lap takes
## the same time at any tick rate; nothing here reads the clock or a random generator, so the same inputs from the same
## state drive the same lap.

## Speed gained per second at full throttle, in pixels a second.
const ACCEL := 640.0
## The share of speed lost per second on the road and on the grass: top speeds of ACCEL / DRAG.
const DRAG := 0.8
const GRASS_DRAG := 3.2
## Speed lost per second while braking, until the car stands still.
const BRAKE := 1000.0
const REVERSE_ACCEL := 320.0
const REVERSE_MAX := 160.0
## The fastest turn at full lock, in radians a second, reached once the car moves at TURN_SPEED.
const TURN_RATE := 2.6
const TURN_SPEED := 140.0
## The sideways acceleration the tyres hold: above GRIP / speed radians a second the car cannot turn tighter.
const GRIP := 1300.0
const RADIUS := 14.0

var position := Vector2.ZERO
## Radians; 0 points along +x.
var heading := 0.0
## Pixels a second along the heading; negative in reverse.
var speed := 0.0
var on_road := true
## The track segment the car is on, kept by Race so the next lookup starts there.
var index := 0


static func at(state: Dictionary) -> Car:
	var car := Car.new()
	car.position = state.get("position", Vector2.ZERO)
	car.heading = float(state.get("heading", 0.0))
	car.speed = float(state.get("speed", 0.0))
	return car


func state() -> Dictionary:
	return {"position": position, "heading": heading, "speed": speed}


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func velocity() -> Vector2:
	return forward() * speed


## throttle: 1 full throttle, -1 full brake (reverse once stopped); steer: -1 full left, 1 full right.
func step(throttle: float, steer: float, dt: float, road := true) -> void:
	on_road = road
	throttle = clampf(throttle, -1.0, 1.0)
	steer = clampf(steer, -1.0, 1.0)
	_turn(steer, dt)
	if throttle >= 0.0 or speed <= 0.0:
		var push := ACCEL * throttle if throttle >= 0.0 else REVERSE_ACCEL * throttle
		speed += push * dt
	else:
		speed = maxf(speed + BRAKE * throttle * dt, 0.0)
	# Drag taken implicitly, speed / (1 + drag * dt): stable at any step, and the top speed is exactly ACCEL / DRAG at
	# every tick rate. (exp() would be smoother, but it comes from each OS's C library, and replays must not drift.)
	var drag := DRAG if road else GRASS_DRAG
	speed /= 1.0 + drag * dt
	speed = maxf(speed, -REVERSE_MAX)
	position += forward() * speed * dt


func _turn(steer: float, dt: float) -> void:
	var moving := absf(speed)
	if moving < 0.001:
		return
	var rate := TURN_RATE * minf(moving / TURN_SPEED, 1.0)
	rate = minf(rate, GRIP / moving)
	# Reversing turns the other way, as a real car's nose does.
	heading = wrapf(heading + steer * rate * signf(speed) * dt, -PI, PI)
