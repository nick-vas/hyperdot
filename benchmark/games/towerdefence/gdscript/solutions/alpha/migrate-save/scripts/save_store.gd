class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, progress (map id -> best stars and seeds kept) and settings
## (volume, locale).
## Version 2 is current; version 1 kept only a list of the maps cleared and the volume, and players still have such files.

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "progress": {}, "settings": {"volume": 1.0, "locale": "en"}}


## The save as the current version, or the defaults when there is none or it cannot be read.
func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	# A damaged save is the player's loss, not an engine error: start from the defaults.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return defaults()
	return migrate(json.data)


## Any version's data as the current version.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := defaults()
	var version := int(raw.get("version", 1))
	if version == 1:
		# Version 1 kept no stars: each map it lists was cleared, with one star.
		var cleared: Variant = raw.get("cleared", [])
		if typeof(cleared) == TYPE_ARRAY:
			for id: Variant in cleared:
				data.progress[str(id)] = {"stars": 1, "lives": 0}
		data.settings.volume = clampf(float(raw.get("volume", 1.0)), 0.0, 1.0)
		return data
	var progress: Variant = raw.get("progress", {})
	if typeof(progress) == TYPE_DICTIONARY:
		for key: Variant in progress:
			var entry: Variant = progress[key]
			if typeof(entry) == TYPE_DICTIONARY:
				data.progress[str(key)] = {"stars": clampi(int(entry.get("stars", 0)), 0, 3), "lives": int(entry.get("lives", 0))}
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.progress = data.get("progress", {})
	out.settings = data.get("settings", out.settings)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	return true
