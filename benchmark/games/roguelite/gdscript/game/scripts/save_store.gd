class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, meta (Meta: embers, vigor, best_floor, runs), run (the run in
## progress as Run.to_dict(), kept at the start of each floor so Continue can carry on, or null) and settings (volume,
## locale).
## Version 2 is current; version 1 kept only the embers and the deepest floor, and players still have such files.

const VERSION := 2
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "meta": Meta.defaults(), "run": null, "settings": {"volume": 1.0, "locale": "en"}}


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
		# Version 1 had no shrine, no runs counted and no run kept: only the bank and the deepest floor.
		data.meta.embers = maxi(0, int(raw.get("embers", 0)))
		data.meta.best_floor = maxi(0, int(raw.get("best", 0)))
		return data
	var meta: Variant = raw.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY:
		data.meta.embers = maxi(0, int(meta.get("embers", 0)))
		data.meta.vigor = clampi(int(meta.get("vigor", 0)), 0, Meta.VIGOR_MAX)
		data.meta.best_floor = maxi(0, int(meta.get("best_floor", 0)))
		data.meta.runs = maxi(0, int(meta.get("runs", 0)))
	var run: Variant = raw.get("run", null)
	if typeof(run) == TYPE_DICTIONARY:
		data.run = run
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.meta = data.get("meta", out.meta)
	out.run = data.get("run", null)
	out.settings = data.get("settings", out.settings)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	return true
