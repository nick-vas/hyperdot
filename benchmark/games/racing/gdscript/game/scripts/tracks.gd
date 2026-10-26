class_name Tracks
extends RefCounted
## The tracks and the rivals, read from data/tracks.json and data/rivals.json.

var rows: Array = []
var rivals: Array = []


static func from_files(tracks_path := "res://data/tracks.json", rivals_path := "res://data/rivals.json") -> Tracks:
	var tracks := Tracks.new()
	tracks.rows = _read_array(tracks_path)
	tracks.rivals = _read_array(rivals_path)
	return tracks


static func _read_array(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func count() -> int:
	return rows.size()


func row(id: int) -> Dictionary:
	for r: Dictionary in rows:
		if int(r.get("id", 0)) == id:
			return r
	return {}


func has_track(id: int) -> bool:
	return not row(id).is_empty()


func track(id: int) -> Track:
	return Track.from_row(row(id))


## The drivers of a race: the player's (null, or a full-pace AI for the bot) and then rival_count rivals.
func drivers_for(rival_count: int, race_seed: int, bot := false) -> Array:
	var out: Array = [AiDriver.new() if bot else null]
	for k in grid_order(rival_count, race_seed):
		var rival: Dictionary = rivals[k]
		out.append(AiDriver.new(float(rival.get("pace", 0.9)), float(rival.get("line", 0.0))))
	return out


## Which rival (an index into rivals) drives each car after the player's: the data's rivals in turn, shuffled by the
## race's seed so the grid differs from race to race.
func grid_order(rival_count: int, race_seed: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = race_seed
	var order: Array[int] = []
	for i in rival_count:
		order.append(i % maxi(rivals.size(), 1))
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	return order
