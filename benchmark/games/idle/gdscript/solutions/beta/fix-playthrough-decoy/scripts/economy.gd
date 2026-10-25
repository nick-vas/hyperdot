class_name Economy
extends RefCounted
## The glow economy, without nodes or the clock: producers bought with glow at prices that grow geometrically,
## upgrades that multiply what they make, and the dawn, the reset that trades a run's glow for embers. Every amount is a
## double (Numbers). The rate is worked out once per change and kept, so a tick costs the same however much is owned.

signal bought(id: String, amount: int)
signal upgraded(id: String)
signal dawned(embers: float)

var catalog: Catalog
var glow := 0.0
## Glow earned since the last dawn, spent or not: what the next dawn pays for.
var run_earned := 0.0
## Glow earned in all runs.
var total_earned := 0.0
## Producer id -> how many are owned.
var owned := {}
## Upgrade id -> true, for those bought this run.
var upgrades := {}
var embers := 0.0
var dawns := 0
## How many times the rate was worked out from scratch: for the performance tests.
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
	return base * (Numbers.power(g, n + amount) - Numbers.power(g, n)) / (g - 1.0)


## The most of a producer the glow pays for now.
func max_affordable(id: String) -> int:
	if catalog.producer(id).is_empty() or cost(id, 1) > glow:
		return 0
	# Double until it costs too much, then halve the gap: exact at the boundary, and no log().
	var low := 1
	var high := 2
	while cost(id, high) <= glow:
		low = high
		high *= 2
	while high - low > 1:
		var middle := low + floori((high - low) / 2.0)
		if cost(id, middle) <= glow:
			low = middle
		else:
			high = middle
	return low

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


## Buys as many of a producer as the glow pays for; how many.
func buy_max(id: String) -> int:
	var amount := max_affordable(id)
	if amount > 0:
		buy(id, amount)
	return amount


## Whether an upgrade is on offer: not bought yet, and its producer owned often enough ("all": all producers together).
func upgrade_unlocked(id: String) -> bool:
	var u := catalog.upgrade(id)
	if u.is_empty() or upgrades.has(id):
		return false
	var target := str(u.target)
	if target == "all":
		var total := 0
		for p_id: Variant in owned:
			total += count(p_id)
		return total >= int(u.needs)
	if target == "tap":
		return true
	return count(target) >= int(u.needs)


func can_upgrade(id: String) -> bool:
	return upgrade_unlocked(id) and float(catalog.upgrade(id).cost) <= glow


func buy_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	glow -= float(catalog.upgrade(id).cost)
	upgrades[id] = true
	_dirty = true
	upgraded.emit(id)
	return true


## What upgrades and milestones multiply a producer by (or the tap, for "tap").
func multiplier(id: String) -> float:
	var m := 1.0
	for u: Dictionary in catalog.upgrades:
		if upgrades.has(str(u.id)) and (str(u.target) == id or (str(u.target) == "all" and id != "tap")):
			m *= float(u.multiplier)
	var every := int(catalog.setting("milestone_every"))
	if id != "tap" and every > 0:
		m *= Numbers.power(catalog.setting("milestone_multiplier"), floori(count(id) / float(every)))
	return m


## What every ember adds to production.
func ember_multiplier() -> float:
	return 1.0 + embers * catalog.setting("ember_bonus")


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


## What one more of a producer would add per second (its next milestone left out).
func unit_rate(id: String) -> float:
	var p := catalog.producer(id)
	return 0.0 if p.is_empty() else float(p.rate) * multiplier(id) * ember_multiplier()


func _recompute() -> void:
	rate_computations += 1
	_rates.clear()
	_rate = 0.0
	for p: Dictionary in catalog.producers:
		var id := str(p.id)
		var r := float(p.rate) * count(id) * multiplier(id) * ember_multiplier()
		_rates[id] = r
		_rate += r
	_dirty = false


## Glow for one press of Gather.
func tap_value() -> float:
	return catalog.setting("tap") * multiplier("tap")


func tap() -> float:
	var value := tap_value()
	earn(value)
	return value


## Lets the given seconds of production pass; what they earned.
func tick(seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var earned := rate() * seconds
	glow = minf(glow + earned, Numbers.MAX)
	return earned


func earn(amount: float) -> void:
	glow = minf(glow + amount, Numbers.MAX)
	run_earned = minf(run_earned + amount, Numbers.MAX)
	total_earned = minf(total_earned + amount, Numbers.MAX)


## Embers a dawn now would give: the square root of the run's glow over the dawn base, rounded down.
func dawn_gain() -> float:
	return floorf(sqrt(maxf(run_earned, glow) / catalog.setting("dawn_base")))


func can_dawn() -> bool:
	return dawn_gain() >= 1.0


## The prestige reset: glow, producers and upgrades go, embers stay and grow. Returns the embers gained (0: not yet).
func dawn() -> float:
	var gain := dawn_gain()
	if gain < 1.0:
		return 0.0
	embers += gain
	dawns += 1
	glow = 0.0
	run_earned = 0.0
	owned.clear()
	upgrades.clear()
	_dirty = true
	dawned.emit(gain)
	return gain


func to_dict() -> Dictionary:
	return {
		"glow": glow,
		"run_earned": run_earned,
		"total_earned": total_earned,
		"owned": owned.duplicate(),
		"upgrades": upgrades.keys(),
		"prestige": {"embers": embers, "dawns": dawns},
	}


## An economy from to_dict()'s data; anything missing or of the wrong kind starts at zero.
static func from_dict(game_catalog: Catalog, data: Dictionary) -> Economy:
	var e := Economy.new(game_catalog)
	e.glow = _amount(data.get("glow", 0.0))
	e.run_earned = _amount(data.get("run_earned", e.glow))
	e.total_earned = maxf(_amount(data.get("total_earned", e.run_earned)), e.run_earned)
	var owned_data: Variant = data.get("owned", {})
	if typeof(owned_data) == TYPE_DICTIONARY:
		for id: Variant in owned_data:
			if not game_catalog.producer(str(id)).is_empty():
				e.owned[str(id)] = maxi(0, int(owned_data[id]))
	var upgrade_data: Variant = data.get("upgrades", [])
	if typeof(upgrade_data) == TYPE_ARRAY:
		for id: Variant in upgrade_data:
			if not game_catalog.upgrade(str(id)).is_empty():
				e.upgrades[str(id)] = true
	var prestige: Variant = data.get("prestige", {})
	if typeof(prestige) == TYPE_DICTIONARY:
		e.embers = _amount(prestige.get("embers", 0.0))
		e.dawns = maxi(0, int(prestige.get("dawns", 0)))
	return e


static func _amount(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return 0.0
	var amount := float(value)
	return clampf(amount, 0.0, Numbers.MAX) if not is_nan(amount) else 0.0
