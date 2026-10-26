class_name SaveStore
extends RefCounted
## The player's save, JSON in user://save.json: version, economy (Economy.to_dict()), saved_at (the latest time the game
## has seen, in Unix seconds, for offline progress) and settings (volume, locale).
## Version 3 is current. Version 2 (the 0.x releases) kept the dawn's embers and count at the top level, beside the
## economy, and players still have such files.

const VERSION := 3
const DEFAULT_PATH := "user://save.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's save.
var enabled := true


func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "economy": {}, "saved_at": 0.0, "settings": {"volume": 1.0, "locale": "en"}}


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
	var economy: Variant = raw.get("economy", {})
	if typeof(economy) == TYPE_DICTIONARY:
		data.economy = economy.duplicate(true)
	var version := int(raw.get("version", 2))
	if version < 3:
		# Version 2 kept the dawn's embers and count beside the economy, not in it.
		data.economy["prestige"] = {"embers": raw.get("embers", 0.0), "dawns": raw.get("dawns", 0)}
	var saved_at: Variant = raw.get("saved_at", 0.0)
	if typeof(saved_at) == TYPE_FLOAT or typeof(saved_at) == TYPE_INT:
		data.saved_at = float(saved_at)
	var settings: Variant = raw.get("settings", {})
	if typeof(settings) == TYPE_DICTIONARY:
		data.settings.volume = clampf(float(settings.get("volume", 1.0)), 0.0, 1.0)
		data.settings.locale = str(settings.get("locale", "en"))
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	out.economy = data.get("economy", {})
	out.saved_at = float(data.get("saved_at", 0.0))
	out.settings = data.get("settings", out.settings)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveStore: cannot write %s" % path)
		return false
	# Full precision: glow past 2^53 comes back as the same double.
	file.store_string(JSON.stringify(out, "  ", true, true))
	file.close()
	if OS.has_feature("web"):
		# The browser keeps user:// in IndexedDB a frame after the file closes; a closed tab would lose it.
		JavaScriptBridge.force_fs_sync()
	return true
