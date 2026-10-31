# The XR numbers xr describes, as plain functions that need no headset and no XR interface, so a unit test can hold
# them. Copy this file into the game (and xr_rig.gd beside it). Used as
#   const XrMath := preload("res://xr_math.gd")
#   var velocity := XrMath.peak_velocity(samples)
#
#   peak_velocity       a throw leaves at the fastest hand speed of the last THROW_WINDOW frames, not the release frame
#   velocity_from_positions   the same speed from two positions, for a pose that reports no velocity
#   world_velocity      a hand velocity (tracking space, metres per second) in the world
#   body_position       the point on the floor under the head, which is where the player's body is
#   rotate_origin_about turns the XROrigin3D around a point so that point does not move in the world
#   blackout            how dark the view goes when the player walks where the body cannot follow
#   active_hand         the controller that does everything when only one is tracked
#   SnapTurn            stick to fixed-angle turns, one turn per push
#   Vignette            a radius that closes at once when the player is moved and opens again after a rest
# The limits are the kit's first guesses, not measurements: tune them with a headset on a player who gets motion sick.
extends RefCounted

# Half-Life: Alyx took the peak of the last ten frames of hand speed (docs/valve.md, item 56).
const THROW_WINDOW := 10


# `samples` holds hand velocities (Vector3, oldest first). Returns the one with the greatest speed among the last
# `window`, or zero when there are none. Taking the peak keeps the speed of the flick when the hand slows in the frames
# before the button is let go; the mean of the last frames would throw softer than the player threw.
static func peak_velocity(samples: Array, window: int = THROW_WINDOW) -> Vector3:
	var peak := Vector3.ZERO
	var best := -1.0
	for i in range(maxi(0, samples.size() - window), samples.size()):
		var v: Vector3 = samples[i]
		var speed := v.length_squared()
		if speed > best:
			best = speed
			peak = v
	return peak


static func velocity_from_positions(previous: Vector3, current: Vector3, delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	return (current - previous) / delta


# XRPose velocities are in the tracking space of the XROrigin3D. `origin_velocity` is how fast the player is being moved
# (a moving platform, a vehicle) in the world, added so a throw from a moving train goes with the train.
static func world_velocity(origin: Transform3D, local_velocity: Vector3, origin_velocity: Vector3 = Vector3.ZERO) -> Vector3:
	return origin.basis * local_velocity + origin_velocity


# `camera_local` is the XRCamera3D's position relative to the XROrigin3D. The body is under the head, at floor height of
# the tracking space; the origin is only the middle of the room.
static func body_position(origin: Transform3D, camera_local: Vector3) -> Vector3:
	return origin * Vector3(camera_local.x, 0.0, camera_local.z)


# Turning the origin about itself swings a player standing away from the room's middle around the room. This turns it
# about `pivot` (a world point, normally body_position) so the player stays where they are.
static func rotate_origin_about(origin: Transform3D, pivot: Vector3, angle_radians: float) -> Transform3D:
	var turn := Transform3D(Basis(Vector3.UP, angle_radians), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
	return (about * origin).orthonormalized()


# How black the view is when the body could not follow the head: `gap` is the distance in metres between where the player
# stands and where the body was left. Nothing under `start`, fully black at `full` and rising smoothly between (the
# manual: the screen "slowly blacks out" as the distance grows past a few centimetres). The two distances are guesses.
static func blackout(gap: float, start: float = 0.03, full: float = 0.15) -> float:
	return clampf(inverse_lerp(start, full, gap), 0.0, 1.0)


# The hand that does everything when one controller is tracked: the preferred one if it is tracked, else the other,
# else "" (use hand tracking, or the flat fallback). Pass XRNode3D.get_has_tracking_data() of each controller.
static func active_hand(left_tracked: bool, right_tracked: bool, preferred: StringName = &"right_hand") -> StringName:
	var order: Array[StringName] = [&"right_hand", &"left_hand"]
	if preferred == &"left_hand":
		order = [&"left_hand", &"right_hand"]
	for hand in order:
		if (hand == &"left_hand" and left_tracked) or (hand == &"right_hand" and right_tracked):
			return hand
	return &""


# Snap turning: a push of the stick past `press` turns once by `angle_degrees`, and the stick must come back under
# `release` before it can turn again. Returns degrees to turn about Y: negative (clockwise from above) for a push right,
# positive for left, 0 otherwise.
class SnapTurn extends RefCounted:
	var angle_degrees := 30.0
	var press := 0.7
	var release := 0.4
	var _armed := true

	func update(stick_x: float) -> float:
		var magnitude := absf(stick_x)
		if _armed and magnitude >= press:
			_armed = false
			return -signf(stick_x) * angle_degrees
		if not _armed and magnitude <= release:
			_armed = true
		return 0.0


# A comfort vignette: radius 1 is open, `min_radius` is the tightest. It closes at once to the radius the movement asks for
# (a slow close shows the motion unframed), stays closed for `hold` seconds after the movement stops, then opens over
# `open_time` seconds. `speed` is metres per second moved by the stick, `turn` degrees per second turned by the stick:
# movement the player makes with their own body never feeds it.
class Vignette extends RefCounted:
	var min_radius := 0.35
	var speed_limit := 3.0
	var turn_limit := 90.0
	var hold := 0.5
	var open_time := 1.0
	var radius := 1.0
	var _rest := 0.0

	func update(speed: float, turn: float, delta: float) -> float:
		var amount := clampf(maxf(absf(speed) / speed_limit, absf(turn) / turn_limit), 0.0, 1.0)
		var target := lerpf(1.0, min_radius, amount)
		if amount > 0.0:
			_rest = 0.0
		else:
			_rest += delta
		if target < radius:
			radius = target
		elif amount == 0.0 and _rest > hold:
			radius = minf(1.0, radius + (1.0 - min_radius) / open_time * delta)
		return radius
