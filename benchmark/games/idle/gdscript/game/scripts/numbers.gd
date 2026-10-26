class_name Numbers
extends RefCounted
## Big numbers. Glow and costs are doubles: exact up to 2^53, past it kept to about 16 significant digits (a relative
## error under 1e-12 is the game's tolerance, tested), and the screen shows three. They are printed with a short name
## per thousand (K, M, B ... Dc), then two letters (aa, ab ... zz), never in scientific notation. Nothing here calls
## pow() or log(), whose last bit can differ between machines: powers are multiplied out.

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
## The most glow the game keeps: a double would reach infinity at 1.8e308.
const MAX := 1e300
## How far a sum of doubles may drift from the exact value, relative to it: what the tests allow.
const TOLERANCE := 1e-12
## 1000^k for every group up to MAX, each parsed from its decimal text so that 1e33 is exactly the double 1e33.
static var _thousands: Array[float] = []


## A number as the screen shows it: whole numbers below 1000 (one decimal below 10), then three significant digits and
## a suffix, rounded down so the screen never promises glow the player does not have.
static func format(value: float) -> String:
	if is_nan(value) or value <= 0.0:
		return "0"
	value = minf(value, MAX)
	if value < 10.0:
		var tenths := floorf(value * 10.0 + 1e-9) / 10.0
		return str(int(tenths)) if tenths == floorf(tenths) else "%.1f" % tenths
	if value < 1000.0:
		return str(int(floorf(value + 1e-9)))
	var group := group_of(value)
	var mantissa := value / thousand(group)
	var digits: String
	if mantissa >= 100.0:
		digits = str(int(floorf(mantissa + 1e-9)))
	elif mantissa >= 10.0:
		digits = "%.1f" % (floorf(mantissa * 10.0 + 1e-9) / 10.0)
	else:
		digits = "%.2f" % (floorf(mantissa * 100.0 + 1e-9) / 100.0)
	return digits + suffix(group)


## The name of 1000^group: the short names first, then aa, ab ... az, ba ... (1e36 is aa).
static func suffix(group: int) -> String:
	if group < SUFFIXES.size():
		return SUFFIXES[group]
	var n := group - SUFFIXES.size()
	return String.chr(97 + floori(n / 26.0) % 26) + String.chr(97 + n % 26)


## The largest k with 1000^k <= value (0 below 1000).
static func group_of(value: float) -> int:
	var k := 0
	while k + 1 < 101 and value >= thousand(k + 1):
		k += 1
	return k


## 1000^k, exact for every k a double can hold.
static func thousand(k: int) -> float:
	if _thousands.is_empty():
		for i in 101:
			_thousands.append(("1e%d" % (3 * i)).to_float())
	return _thousands[clampi(k, 0, 100)]


## base^exponent for a whole exponent, by squaring: the same result on every machine.
static func power(base: float, exponent: int) -> float:
	var result := 1.0
	var b := base
	var e := absi(exponent)
	while e > 0:
		if e & 1:
			result *= b
		b *= b
		e >>= 1
	return result if exponent >= 0 else 1.0 / result


## A rate per second, as the screen shows it.
static func format_rate(per_second: float) -> String:
	return "%s/s" % format(per_second)


## Whether two doubles agree within the game's tolerance.
static func close(a: float, b: float, tolerance := TOLERANCE) -> bool:
	return absf(a - b) <= tolerance * maxf(absf(a), absf(b))
