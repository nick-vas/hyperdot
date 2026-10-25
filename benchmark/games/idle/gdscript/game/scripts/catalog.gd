class_name Catalog
extends RefCounted
## The game's numbers, all from data: producers (data/producers.json), upgrades (data/upgrades.json) and the economy's
## settings (data/economy.json). The data runner checks their shape (data.json); the tests check what they mean.

const PRODUCERS_PATH := "res://data/producers.json"
const UPGRADES_PATH := "res://data/upgrades.json"
const ECONOMY_PATH := "res://data/economy.json"

## Producers in shop order: { id, name (a translation key), cost, growth, rate }.
var producers: Array[Dictionary] = []
## Upgrades in shop order: { id, name, target (a producer id, "all" or "tap"), multiplier, cost, needs }.
var upgrades: Array[Dictionary] = []
## The economy's settings by id (tap, milestone_every, dawn_base ...).
var settings := {}
var _producers_by_id := {}
var _upgrades_by_id := {}


static func from_files() -> Catalog:
	return from_data(_read(PRODUCERS_PATH), _read(UPGRADES_PATH), _read(ECONOMY_PATH))


static func from_data(producer_rows: Array, upgrade_rows: Array, setting_rows: Array) -> Catalog:
	var catalog := Catalog.new()
	for row: Variant in producer_rows:
		if typeof(row) == TYPE_DICTIONARY:
			catalog.producers.append(row)
			catalog._producers_by_id[str(row.id)] = row
	for row: Variant in upgrade_rows:
		if typeof(row) == TYPE_DICTIONARY:
			catalog.upgrades.append(row)
			catalog._upgrades_by_id[str(row.id)] = row
	for row: Variant in setting_rows:
		if typeof(row) == TYPE_DICTIONARY:
			catalog.settings[str(row.id)] = float(row.value)
	return catalog


static func _read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Catalog: %s is not a JSON array" % path)
		return []
	return parsed


func producer(id: String) -> Dictionary:
	return _producers_by_id.get(id, {})


func upgrade(id: String) -> Dictionary:
	return _upgrades_by_id.get(id, {})


func setting(id: String) -> float:
	return float(settings.get(id, 0.0))
