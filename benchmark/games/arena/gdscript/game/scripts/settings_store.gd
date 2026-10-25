class_name SettingsStore
extends RefCounted
## The player's settings and record, JSON in user://settings.json: version, volume (0 to 1), locale, played and won
## (matches). Version 2 is current; version 1 kept the volume in decibels as volume_db and the language as language, and
## players still have such files.

const VERSION := 2
const DEFAULT_PATH := "user://settings.json"

var path: String
## Off with --no-save, so bot runs and tests never touch the player's file.
var enabled := true


func _init(settings_path := DEFAULT_PATH) -> void:
	path = settings_path


static func defaults() -> Dictionary:
	return {"version": VERSION, "volume": 1.0, "locale": "en", "played": 0, "won": 0}


## The settings as the current version, or the defaults when there are none or they cannot be read.
func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	# A damaged file is the player's loss, not an engine error: start from the defaults.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return defaults()
	return migrate(json.data)


## Any version's data as the current version.
static func migrate(raw: Dictionary) -> Dictionary:
	var data := defaults()
	var version := int(raw.get("version", 1))
	if version == 1:
		# Version 1 stored decibels (0 is full volume) and called the locale "language"; it kept no record.
		data.volume = clampf(db_to_linear(float(raw.get("volume_db", 0.0))), 0.0, 1.0)
		data.locale = str(raw.get("language", "en"))
		return data
	data.volume = clampf(float(raw.get("volume", 1.0)), 0.0, 1.0)
	data.locale = str(raw.get("locale", "en"))
	data.played = maxi(int(raw.get("played", 0)), 0)
	data.won = maxi(int(raw.get("won", 0)), 0)
	return data


func write(data: Dictionary) -> bool:
	if not enabled:
		return false
	var out := defaults()
	for key: String in ["volume", "locale", "played", "won"]:
		out[key] = data.get(key, out[key])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SettingsStore: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(out, "  "))
	return true
