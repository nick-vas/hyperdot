class_name Offline
extends RefCounted
## Progress while the game was closed, from the time saved and the time now, both given by the caller (scripts/ never
## reads the clock, so this is testable and the same on every machine). A clock set back pays nothing, the time paid is
## capped, and the time kept for the next save never goes back, so a clock put right again does not pay twice.


## The seconds away that are paid for.
static func seconds_away(saved_at: float, now: float, cap: float) -> float:
	return clampf(now - saved_at, 0.0, cap)


## The time to keep for the next save: the latest the game has seen.
static func seen_at(saved_at: float, now: float) -> float:
	return now


## Pays an economy for the time away; the seconds paid and the glow they earned.
static func apply(economy: Economy, saved_at: float, now: float) -> Dictionary:
	var seconds := seconds_away(saved_at, now, economy.catalog.setting("offline_cap_seconds"))
	return {"seconds": seconds, "glow": economy.tick(seconds)}
