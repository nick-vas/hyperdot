class_name Floors
extends RefCounted
## The crypt's floors (data/floors.json) and the kinds of enemy on them (data/enemies.json). A run goes down them in
## order; clearing the last one is victory.

const FLOORS_PATH := "res://data/floors.json"
const ENEMIES_PATH := "res://data/enemies.json"

## Enemy id -> its row of data/enemies.json.
var kinds := {}
var _floors := {}


static func from_files(floors_path := FLOORS_PATH, enemies_path := ENEMIES_PATH) -> Floors:
	var floors := Floors.new()
	for entry: Variant in _read(enemies_path):
		if typeof(entry) == TYPE_DICTIONARY:
			floors.kinds[str(entry.get("id", ""))] = entry
	for entry: Variant in _read(floors_path):
		if typeof(entry) == TYPE_DICTIONARY:
			floors._floors[int(entry.get("id", 0))] = entry
	return floors


static func _read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Floors: %s is not a JSON array" % path)
		return []
	return parsed


func count() -> int:
	return _floors.size()


func has_floor(number: int) -> bool:
	return _floors.has(number)


## A floor's row of data/floors.json; empty when there is no such floor.
func spec(number: int) -> Dictionary:
	return _floors.get(number, {})


func kind(id: String) -> Dictionary:
	return kinds.get(id, {})
