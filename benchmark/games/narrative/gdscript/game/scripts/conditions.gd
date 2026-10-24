class_name Conditions
extends RefCounted
## A choice's needs, in the kit's criteria grammar (the data runner checks the syntax): criteria joined by ";", each
## "!flag" (the flag is 0) or "flag op number" with op one of = < <= > >=. Empty needs always hold.


## The criteria of a text, each { "key", "op", "value" }; "!" is op "!" with value 0.
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in text.split(";", false):
		var item := part.strip_edges()
		if item.is_empty():
			continue
		if item.begins_with("!"):
			out.append({"key": item.substr(1).strip_edges(), "op": "!", "value": 0})
			continue
		# Two-letter operators first, so "<=" is not read as "<" followed by "=".
		for op: String in ["<=", ">=", "=", "<", ">"]:
			var at := item.find(op)
			if at > 0:
				out.append({"key": item.substr(0, at).strip_edges(), "op": op, "value": int(item.substr(at + op.length()).strip_edges())})
				break
	return out


## Whether every criterion holds for the flags (a missing flag is 0).
static func holds(text: String, flags: Dictionary) -> bool:
	for criterion in parse(text):
		var value := int(flags.get(criterion.key, 0))
		var want: int = criterion.value
		var ok: bool
		match criterion.op:
			"!":
				ok = value == 0
			"=":
				ok = value == want
			"<":
				ok = value < want
			"<=":
				ok = value <= want
			">":
				ok = value > want
			">=":
				ok = value >= want
			_:
				ok = false
		if not ok:
			return false
	return true


## The flags a text reads.
static func keys(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for criterion in parse(text):
		out.append(criterion.key)
	return out
