class_name AiDriver
extends RefCounted
## Drives a car along the racing line: it steers for a point ahead on the line (further ahead the faster it goes) and
## keeps to the track's speed profile, scaled by its pace, lifting and braking before the bends. The rivals and the bot
## are all this driver; only pace and their line differ.

## How far ahead it aims, in pixels, and how much further per pixel a second of speed.
const AIM_BASE := 70.0
const AIM_PER_SPEED := 0.3
## Steering per radian between the heading and the aim.
const STEER_GAIN := 2.4
## Over the planned speed by this much, it brakes instead of lifting.
const BRAKE_MARGIN := 40.0

## 1 drives the profile as planned; a rival at 0.9 takes every part of the lap at nine tenths.
var pace := 1.0
## Pixels to the right of the centre line it drives on.
var line_offset := 0.0


func _init(driver_pace := 1.0, offset := 0.0) -> void:
	pace = driver_pace
	line_offset = offset


## Throttle (x) and steering (y) for this tick.
func decide(car: Car, track: Track) -> Vector2:
	var aim_distance := AIM_BASE + AIM_PER_SPEED * maxf(car.speed, 0.0)
	var target := _point_ahead(track, car.index, aim_distance)
	var wanted := (target - car.position).angle()
	var steer := clampf(angle_difference(car.heading, wanted) * STEER_GAIN, -1.0, 1.0)
	# The slowest planned speed over the stretch the car covers in the next half second.
	var limit := INF
	var reach := maxi(int(maxf(car.speed, 0.0) * 0.5 / maxf(track.segment_length(car.index), 1.0)), 1)
	for k in reach + 1:
		limit = minf(limit, track.speed_profile[posmod(car.index + k, track.point_count())])
	limit *= pace
	var throttle := pace
	if car.speed > limit + BRAKE_MARGIN:
		throttle = -1.0
	elif car.speed > limit:
		throttle = 0.0
	return Vector2(throttle, steer)


func _point_ahead(track: Track, from: int, distance: float) -> Vector2:
	var i := from
	var left := distance
	while left > track.segment_length(posmod(i, track.point_count())):
		left -= track.segment_length(posmod(i, track.point_count()))
		i += 1
	var a := track.point(i)
	var b := track.point(i + 1)
	var on_line := a.lerp(b, left / maxf(a.distance_to(b), 0.001))
	return on_line + track.tangent(i).orthogonal() * line_offset
