class_name Progress
extends RefCounted
## What a save says about the maps: each one's best result (stars and the seeds kept), and which maps are open. The
## first map is always open; the next opens once the one before it is cleared.


## Stars for a cleared map: 3 with no seed lost, 2 with at least half kept, 1 otherwise.
static func stars_for(lives: int, start_lives: int) -> int:
	if lives >= start_lives:
		return 3
	return 2 if lives * 2 >= start_lives else 1


## Records a cleared map, keeping the best result: more stars, then more seeds kept.
static func record(save: Dictionary, map_id: String, lives: int, start_lives: int) -> void:
	var progress: Dictionary = save.progress
	var best: Dictionary = progress.get(map_id, {"stars": 0, "lives": 0})
	var stars := stars_for(lives, start_lives)
	if stars > int(best.stars) or (stars == int(best.stars) and lives > int(best.lives)):
		progress[map_id] = {"stars": stars, "lives": lives}


static func stars(save: Dictionary, map_id: String) -> int:
	return int(save.progress.get(map_id, {}).get("stars", 0))


static func is_cleared(save: Dictionary, map_id: String) -> bool:
	return stars(save, map_id) > 0


## Whether the map at this place in the campaign (from 1) may be played.
static func is_unlocked(save: Dictionary, catalog: Catalog, index: int) -> bool:
	if index <= 1:
		return true
	var before := catalog.map_at(index - 1)
	return not before.is_empty() and is_cleared(save, str(before.id))


static func total_stars(save: Dictionary) -> int:
	var total := 0
	for key: String in save.progress:
		total += int(save.progress[key].get("stars", 0))
	return total
