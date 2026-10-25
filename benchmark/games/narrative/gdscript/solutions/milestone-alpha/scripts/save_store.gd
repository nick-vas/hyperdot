class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, story (the story in progress as Story.to_dict(): node, flags
## and history, or null), endings (the ids of the endings found) and settings (volume, locale). The story is saved at
## every node, so Continue carries on from the last line shown.

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "story": null, "endings": [], "settings": {"volume": 1.0, "locale": "en"}}


## The save as the current version, or the defaults when there is none or it cannot be read.
func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	# A damaged save is the player's loss, not an engine error: start from the defaults.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return defaults()
	return migrate(json.data)


## The saved data, with defaults for anything missing.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := defaults()
	var story: Variant = raw.get("story", null)
	if typeof(story) == TYPE_DICTIONARY:
		data.story = story
	data.endings = _ids(raw.get("endings", []))
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	return data


## Adds an ending to those found, once.
static func record_ending(data: Dictionary, ending_id: String) -> void:
	if not data.endings.has(ending_id):
		data.endings.append(ending_id)


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.story = data.get("story", null)
	out.endings = data.get("endings", [])
	out.settings = data.get("settings", out.settings)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	return true


static func _ids(value: Variant) -> Array:
	var out := []
	if typeof(value) == TYPE_ARRAY:
		for id: Variant in value:
			if not out.has(str(id)):
				out.append(str(id))
	return out
