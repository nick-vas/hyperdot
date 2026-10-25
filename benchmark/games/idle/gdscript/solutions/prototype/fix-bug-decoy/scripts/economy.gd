class_name Economy
extends RefCounted
## The glow economy, without nodes or the clock: producers bought with glow at prices that grow geometrically, and
## Gather. Every amount is a double (Numbers). The rate is worked out once per change and kept, so a tick costs the same
## however much is owned.

signal bought(id: String, amount: int)

var catalog: Catalog
var glow := 0.0
## Producer id -> how many are owned.
var owned := {}
## How many times the rate was worked out from scratch.
var rate_computations := 0
var _rate := 0.0
var _rates := {}
var _dirty := true


func _init(game_catalog: Catalog = null) -> void:
	catalog = game_catalog if game_catalog != null else Catalog.from_files()


func count(id: String) -> int:
	return int(owned.get(id, 0))


## What the next amount of a producer cost together, at its price now.
func cost(id: String, amount := 1) -> float:
	var p := catalog.producer(id)
	if p.is_empty() or amount < 1:
		return INF
	var base := float(p.cost)
	var g := float(p.growth)
	var n := count(id)
	if amount == 1:
		return base * Numbers.power(g, n)
	# The sum of the next amount prices, base * g^n + ... + base * g^(n + amount - 1).
	return base * Numbers.power(g, n) * amount


func can_buy(id: String, amount := 1) -> bool:
	return amount >= 1 and not catalog.producer(id).is_empty() and cost(id, amount) <= glow


func buy(id: String, amount := 1) -> bool:
	if not can_buy(id, amount):
		return false
	glow -= cost(id, amount)
	owned[id] = count(id) + amount
	_dirty = true
	bought.emit(id, amount)
	return true


## What milestones multiply a producer by: every milestone_every owned, milestone_multiplier.
func multiplier(id: String) -> float:
	var every := int(catalog.setting("milestone_every"))
	if every <= 0:
		return 1.0
	return Numbers.power(catalog.setting("milestone_multiplier"), floori(count(id) / float(every)))


## Glow per second from everything owned.
func rate() -> float:
	if _dirty:
		_recompute()
	return _rate


## Glow per second from one producer.
func producer_rate(id: String) -> float:
	if _dirty:
		_recompute()
	return float(_rates.get(id, 0.0))


func _recompute() -> void:
	rate_computations += 1
	_rates.clear()
	_rate = 0.0
	for p: Dictionary in catalog.producers:
		var id := str(p.id)
		var r := float(p.rate) * count(id) * multiplier(id)
		_rates[id] = r
		_rate += r
	_dirty = false


## Glow for one press of Gather.
func tap_value() -> float:
	return catalog.setting("tap")


func tap() -> float:
	var value := tap_value()
	earn(value)
	return value


## Lets the given seconds of production pass; what they earned.
func tick(seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var earned := rate() * seconds
	earn(earned)
	return earned


func earn(amount: float) -> void:
	glow = minf(glow + amount, Numbers.MAX)
