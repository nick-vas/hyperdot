class_name ChaseCamera
extends Camera2D
## Follows the player's car from above. It looks ahead along the car's velocity, so more of the road to come shows, and
## eases towards that at rates per second (exponential, so it moves the same at any frame rate and through a hitch);
## however hard the car turns, the car never gets further than MAX_LAG from the middle of the view. It moves in
## _process, every drawn frame, following the car's interpolated position.

## How quickly the view catches up with where it wants to be, per second.
const FOLLOW_RATE := 6.0
## The look-ahead: this many seconds of the car's velocity, at most MAX_LOOK pixels, eased at LOOK_RATE.
const LOOK_AHEAD := 0.35
const MAX_LOOK := 220.0
const LOOK_RATE := 3.0
## The car always stays within this many pixels of the middle of the view.
const MAX_LAG := 240.0

## The point the view is centred on.
var focus := Vector2.ZERO
var _look := Vector2.ZERO


func _init() -> void:
	# With physics interpolation on, Godot moves a Camera2D's own update to physics ticks anyway; saying so up front
	# keeps it from warning. The view still follows every drawn frame: follow() sets the position itself.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


## Jumps straight to the car, at the start of a race.
func reset_to(target: Vector2) -> void:
	focus = target
	_look = Vector2.ZERO
	position = focus
	reset_smoothing()


func follow(target: Vector2, velocity: Vector2, delta: float) -> void:
	var look := (velocity * LOOK_AHEAD).limit_length(MAX_LOOK)
	_look = _look.lerp(look, 1.0 - exp(-LOOK_RATE * delta))
	focus = focus.lerp(target + _look, 1.0 - exp(-FOLLOW_RATE * delta))
	var behind := target - focus
	if behind.length() > MAX_LAG:
		focus = target - behind.limit_length(MAX_LAG)
	position = focus
