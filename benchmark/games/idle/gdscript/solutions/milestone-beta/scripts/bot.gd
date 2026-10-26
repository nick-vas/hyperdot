class_name Bot
extends RefCounted
## The --autoplay player. Each decision: dawn once a dawn would at least double the embers, else take any upgrade it can
## pay for, else buy the producer that pays its price back soonest, or wait for it. With nothing to wait for, it gathers.
## Deterministic: the same economy gives the same choice.

## What to do now: { "kind": "dawn" | "upgrade" | "buy" | "gather" | "wait", "id": the upgrade or producer }.
static func next_action(economy: Economy) -> Dictionary:
	var gain := economy.dawn_gain()
	if gain >= 1.0 and gain >= economy.embers:
		return {"kind": "dawn", "id": ""}
	for u: Dictionary in economy.catalog.upgrades:
		if economy.can_upgrade(str(u.id)):
			return {"kind": "upgrade", "id": str(u.id)}
	var best := ""
	var best_payback := INF
	for p: Dictionary in economy.catalog.producers:
		var id := str(p.id)
		var payback := economy.cost(id, 1) / maxf(economy.unit_rate(id), 1e-9)
		if payback < best_payback:
			best_payback = payback
			best = id
	if best != "" and economy.can_buy(best):
		return {"kind": "buy", "id": best}
	if economy.rate() <= 0.0:
		return {"kind": "gather", "id": ""}
	return {"kind": "wait", "id": best}


## Carries out next_action(); what it did.
static func act(economy: Economy) -> Dictionary:
	var action := next_action(economy)
	match action.kind:
		"dawn":
			economy.dawn()
		"upgrade":
			economy.buy_upgrade(action.id)
		"buy":
			economy.buy(action.id)
		"gather":
			economy.tap()
	return action
