# The script for the XROrigin3D of a game that runs with or without a headset (xr skill). Copy it into the game next to
# xr_math.gd. Children: an XRCamera3D and two XRController3D whose `tracker` is left_hand and right_hand.
#
# Without an XR interface (no runtime, no headset, a CI machine) the rig starts in Mode.FLAT: nothing is initialized,
# the controllers report no tracking, and every method here still answers, so a flow or a unit test runs the game's own
# logic. With one controller tracked, active_hand() names it and the game binds everything to that hand.
extends XROrigin3D

const XrMath := preload("res://xr_math.gd")

enum Mode { FLAT, XR }

signal mode_changed(new_mode: Mode)

@export var interface_name := "OpenXR"
@export var preferred_hand: StringName = &"right_hand"

var mode := Mode.FLAT
var _samples := {&"left_hand": [], &"right_hand": []}
var _last_position := {}


func _ready() -> void:
	start()


# OpenXR is started before the project loads, so it is only checked here; other interfaces would need initialize().
func start() -> bool:
	var interface := XRServer.find_interface(interface_name)
	var running := interface != null and interface.is_initialized()
	if running:
		get_viewport().use_xr = true
	_set_mode(Mode.XR if running else Mode.FLAT)
	return running


func controller(hand: StringName) -> XRController3D:
	for child in get_children():
		if child is XRController3D and (child as XRController3D).tracker == hand:
			return child
	return null


func active_hand() -> StringName:
	return XrMath.active_hand(_tracked(&"left_hand"), _tracked(&"right_hand"), preferred_hand)


# Keeps the last XrMath.THROW_WINDOW velocities of each hand. Called every physics frame; a hand that is not tracked
# forgets its samples, so a hand that comes back never throws with the speed it had before it was lost.
func _physics_process(delta: float) -> void:
	for hand in _samples:
		var c := controller(hand)
		if c == null or not c.get_has_tracking_data():
			_samples[hand].clear()
			_last_position.erase(hand)
			continue
		var velocity := c.get_pose().linear_velocity
		if velocity == Vector3.ZERO and _last_position.has(hand):
			velocity = XrMath.velocity_from_positions(_last_position[hand], c.position, delta)
		_last_position[hand] = c.position
		record_sample(hand, velocity)


func record_sample(hand: StringName, local_velocity: Vector3) -> void:
	var samples: Array = _samples[hand]
	samples.append(local_velocity)
	if samples.size() > XrMath.THROW_WINDOW:
		samples.pop_front()


# The world velocity to give a thrown object when `hand` lets go; forgets the samples, so a catch and a second throw do
# not reuse them. `player_velocity` is how fast the game is moving the player (a vehicle), not the room-scale walking.
func release_velocity(hand: StringName, player_velocity: Vector3 = Vector3.ZERO) -> Vector3:
	var velocity := XrMath.world_velocity(global_transform, XrMath.peak_velocity(_samples[hand]), player_velocity)
	_samples[hand].clear()
	return velocity


func _tracked(hand: StringName) -> bool:
	var c := controller(hand)
	return c != null and c.get_has_tracking_data()


func _set_mode(new_mode: Mode) -> void:
	if new_mode != mode:
		mode = new_mode
		mode_changed.emit(mode)
