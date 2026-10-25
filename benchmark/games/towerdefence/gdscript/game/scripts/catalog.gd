class_name Catalog
extends RefCounted
## The game's data: towers and their upgrades, pests, maps and their waves (data/*.json, checked by the data runner).
## Read-only once loaded; a battle copies what it needs.

const DATA_DIR := "res://data"

## Tower id -> its row (cost, range, damage, reload, shot_speed, splash, slow), in file order.
var towers := {}
var tower_ids: Array[String] = []
## "tower:level" -> the upgrade row that buys that level.
var upgrades := {}
var enemies := {}
## The maps in campaign order.
var maps: Array[Dictionary] = []
## Map id -> its waves in order, each { "number", "bonus", "groups": [{ "enemy", "count", "gap", "delay" }] }.
var waves := {}


static func from_files(dir := DATA_DIR) -> Catalog:
	return from_tables(_read(dir + "/towers.json"), _read(dir + "/upgrades.json"), _read(dir + "/enemies.json"),
		_read(dir + "/maps.json"), _read(dir + "/waves.json"), _read(dir + "/groups.json"))


static func from_tables(tower_rows: Array, upgrade_rows: Array, enemy_rows: Array, map_rows: Array, wave_rows: Array, group_rows: Array) -> Catalog:
	var catalog := Catalog.new()
	for row: Dictionary in tower_rows:
		var id := str(row.id)
		catalog.towers[id] = {
			"id": id, "name": str(row.get("name", "")), "cost": int(row.cost), "range": float(row["range"]),
			"damage": int(row.damage), "reload": int(row.reload), "shot_speed": float(row.shot_speed),
			"splash": float(row.get("splash", 0.0)), "slow": float(row.get("slow", 0.0)),
		}
		catalog.tower_ids.append(id)
	for row: Dictionary in upgrade_rows:
		catalog.upgrades["%s:%d" % [row.tower, int(row.level)]] = {
			"cost": int(row.cost), "damage": int(row.damage), "range": float(row["range"]), "reload": int(row.reload),
		}
	for row: Dictionary in enemy_rows:
		catalog.enemies[str(row.id)] = {
			"id": str(row.id), "name": str(row.get("name", "")), "hp": int(row.hp), "speed": float(row.speed),
			"reward": int(row.reward), "leak": int(row.leak), "size": float(row.get("size", 0.25)),
		}
	for row: Dictionary in map_rows:
		catalog.maps.append({
			"id": str(row.id), "name": str(row.get("name", "")), "order": int(row.order), "gold": int(row.gold),
			"lives": int(row.lives), "rows": Array(row.rows),
		})
	catalog.maps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.order < b.order)
	var by_id := {}
	for row: Dictionary in wave_rows:
		var wave := {"id": str(row.id), "number": int(row.number), "bonus": int(row.bonus), "groups": []}
		by_id[wave.id] = wave
		var list: Array = catalog.waves.get(str(row.map), [])
		list.append(wave)
		catalog.waves[str(row.map)] = list
	for row: Dictionary in group_rows:
		var wave: Dictionary = by_id.get(str(row.wave), {})
		if not wave.is_empty():
			wave.groups.append({"enemy": str(row.enemy), "count": int(row.count), "gap": int(row.gap), "delay": int(row.get("delay", 0))})
	for list: Array in catalog.waves.values():
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.number < b.number)
	return catalog


static func _read(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Catalog: %s is not a JSON array" % path)
		return []
	return parsed


func has_tower(id: String) -> bool:
	return towers.has(id)


func cost(id: String) -> int:
	return int(towers[id].cost) if towers.has(id) else 0


## What the upgrade to a level costs; 0 when there is no such upgrade.
func upgrade_cost(id: String, level: int) -> int:
	return int(upgrades.get("%s:%d" % [id, level], {}).get("cost", 0))


func max_level(id: String) -> int:
	var level := 1
	while upgrades.has("%s:%d" % [id, level + 1]):
		level += 1
	return level


## A tower's numbers at a level: the base row with each upgrade up to that level laid over it.
func stats(id: String, level: int) -> Dictionary:
	var out: Dictionary = towers[id].duplicate()
	for step in range(2, level + 1):
		var upgrade: Dictionary = upgrades.get("%s:%d" % [id, step], {})
		for key: String in ["damage", "range", "reload"]:
			if upgrade.has(key):
				out[key] = upgrade[key]
	return out


func map_count() -> int:
	return maps.size()


## The map at a place in the campaign, counted from 1; empty when there is none.
func map_at(index: int) -> Dictionary:
	return maps[index - 1] if index >= 1 and index <= maps.size() else {}


func map_index(id: String) -> int:
	for i in maps.size():
		if maps[i].id == id:
			return i + 1
	return 0


func waves_for(map_id: String) -> Array:
	return waves.get(map_id, [])
