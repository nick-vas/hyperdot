class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, unlocked (the furthest track open), best (each track's best
## lap in milliseconds, by track id as text), ghosts (the best lap's Ghost.to_dict, by track id), settings (volume,
## locale) and controls (Controls.to_dict). Version 2 is current; version 1 kept only each track's best lap in seconds,
## and players still have such files.

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "unlocked": 1, "best": {}, "ghosts": {}, "settings": {"volume": 1.0, "locale": "en"}, "controls": {}}


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
	var best: Variant = raw.get("best", {})
	if version == 1:
		# Version 1 timed laps in seconds and unlocked a track once the one before had a time.
		if typeof(best) == TYPE_DICTIONARY:
			for id: Variant in best:
				data.best[str(int(id))] = roundi(float(best[id]) * 1000.0)
				data.unlocked = maxi(data.unlocked, int(id) + 1)
		return data
	data.unlocked = maxi(1, int(raw.get("unlocked", 1)))
	if typeof(best) == TYPE_DICTIONARY:
		for id: Variant in best:
			data.best[str(id)] = int(best[id])
	var ghosts: Variant = raw.get("ghosts", {})
	if typeof(ghosts) == TYPE_DICTIONARY:
		data.ghosts = ghosts
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	var controls: Variant = raw.get("controls", {})
	if typeof(controls) == TYPE_DICTIONARY:
		data.controls = controls
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.unlocked = int(data.get("unlocked", 1))
	out.best = data.get("best", {})
	out.ghosts = data.get("ghosts", {})
	out.settings = data.get("settings", out.settings)
	out.controls = data.get("controls", {})
	# Written beside the save and moved over it, so a crash mid-write never leaves half a file.
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK


## Keeps a finished lap when it is the track's best: its time and its ghost. True when it was the best.
static func record_lap(data: Dictionary, track_id: int, lap_ms: int, ghost: Ghost) -> bool:
	var key := str(track_id)
	if data.best.has(key) and int(data.best[key]) <= lap_ms:
		return false
	data.best[key] = lap_ms
	if ghost != null:
		data.ghosts[key] = ghost.to_dict()
	return true
