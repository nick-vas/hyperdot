# The `placement` runner's half inside Godot: templates/placement_check.gd on the levels placement.json names, with each
# limit read from the gameplay script constant placement.json names (never a copy of the number).
#   godot --headless --path <project> -s placement.gd -- --check=<kit>/templates/placement_check.gd
# placement.json, in the project folder:
#   { "levels": ["res://levels", "res://extra/arena.tscn"],
#     "limits": { "reach": "res://player.gd:REACH", "zipline_max_angle": "res://zipline.gd:MAX_ANGLE_DEGREES",
#                 "eye_height": 1.7 } }
# "levels" are folders (every .tscn under them, as PlacementCheck.scenes_in finds them) or scenes. "limits" sets the
# check's properties: "<script>:<CONSTANT>" reads a constant of a GDScript, or of a C# file ("res://Player.cs:Reach",
# a `const` or `static readonly` field set to a number, true, false, a plain string or arithmetic on the file's other
# such fields, read from the source, since Godot gives no constants for a C# script), anything else is the value itself.
# Prints "@@placement-scene <path>" per scene checked, "@@placement <finding>" per finding (PlacementCheck's lines),
# "@@placement-summary <line>" for its summary and "@@placement-error <message>" for what stopped it. Exits 0; the
# runner judges.
extends SceneTree

var _opt := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			_opt[arg.get_slice("=", 0).trim_prefix("--")] = arg.substr(arg.find("=") + 1)
	_run.call_deferred()


func _fail(message: String) -> void:
	print("@@placement-error " + message)
	quit(0)


func _run() -> void:
	var check_class := load(str(_opt.get("check", ""))) as GDScript
	if check_class == null:
		_fail("the kit's placement_check.gd did not load from %s" % _opt.get("check", ""))
		return
	var text := FileAccess.get_file_as_string("res://placement.json")
	var config = JSON.parse_string(text)
	if not config is Dictionary:
		_fail("placement.json is not a JSON object")
		return
	for key in config:
		if not key in ["levels", "limits"]:
			_fail("placement.json: unknown setting '%s' (settings: levels, limits)" % key)
			return
	var check = check_class.new()
	var limits = config.get("limits", {})
	if not limits is Dictionary:
		_fail("placement.json: limits is not an object")
		return
	for name in limits:
		if not name in check or name in ["findings", "exemptions", "ready_frames"]:
			_fail("placement.json: '%s' is not a limit of placement_check.gd" % name)
			return
		var value = limits[name]
		if value is String and value.contains(":") and value.begins_with("res://") and value.get_slice(":", value.get_slice_count(":") - 1).is_valid_identifier():
			var constant: String = value.get_slice(":", value.get_slice_count(":") - 1)
			var path: String = value.substr(0, value.length() - constant.length() - 1)
			var constants := {}
			if path.ends_with(".cs"):
				if not FileAccess.file_exists(path):
					_fail("placement.json: limit '%s' names %s, which does not exist" % [name, path])
					return
				constants = _cs_constants(FileAccess.get_file_as_string(path))
				if constants.get(constant) is Callable:
					_fail("placement.json: limit '%s' names %s, whose %s is %s: the runner reads numbers, true, false, plain strings and arithmetic on the file's other constants" % [name, path, constant, constants[constant].call()])
					return
			else:
				var script := load(path) as Script
				if script == null:
					_fail("placement.json: limit '%s' names %s, which does not load" % [name, path])
					return
				constants = script.get_script_constant_map()
			if not constants.has(constant):
				_fail("placement.json: limit '%s' names %s, which has no constant %s (it has: %s)" % [name, path, constant, ", ".join(constants.keys())])
				return
			value = constants[constant]
		var current = check.get(name)
		if typeof(current) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			value = int(value)
		if typeof(current) != TYPE_NIL and typeof(value) != typeof(current) and not (typeof(current) == TYPE_FLOAT and typeof(value) == TYPE_INT):
			_fail("placement.json: limit '%s' is %s, not a %s" % [name, type_string(typeof(value)), type_string(typeof(current))])
			return
		check.set(name, value)
	var paths: Array[String] = []
	for level in config.get("levels", []):
		if str(level).ends_with(".tscn"):
			paths.append(str(level))
		else:
			paths.append_array(check_class.scenes_in(str(level)))
	if paths.is_empty():
		_fail("placement.json: no scenes under %s" % ", ".join(config.get("levels", [])))
		return
	# Its own counts file: a placement test the game also runs keeps its own change since the last run.
	check.counts_file = "res://.godot/placement-runner-counts.json"
	var findings: Array[String] = await check.check_scenes(root, paths)
	for path in paths:
		print("@@placement-scene " + path)
	for finding in findings:
		print("@@placement " + finding)
	for line in check.summary().split("\n", false):
		print("@@placement-summary " + line)
	quit(0)


# The constants of a C# source, by name: `const` and `static readonly` fields set to a literal, or to arithmetic on such
# fields of the same file (Godot's Expression, with C#'s 2f written 2.0 so 1 / 2f stays 0.5). A field set to anything
# else maps to a Callable that returns its text, so the caller can say why it is not read.
func _cs_constants(source: String) -> Dictionary:
	var code := RegEx.create_from_string("/\\*[\\s\\S]*?\\*/|//[^\\n]*").sub(source, "", true)
	var field := RegEx.create_from_string("\\b(?:const|static\\s+readonly)\\s+[A-Za-z_][\\w.]*\\??\\s+([A-Za-z_]\\w*)\\s*=\\s*([^;]+);")
	var integer := RegEx.create_from_string("^-?[0-9][0-9_]*[uUlL]*$")
	var real := RegEx.create_from_string("^-?(?:[0-9][0-9_]*)?(?:\\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9]+)?[fFdDmM]?$")
	var text := RegEx.create_from_string("^\"([^\"\\\\]*)\"$")
	var found := {}
	for m in field.search_all(code):
		var literal := m.get_string(2).strip_edges()
		var digits := literal.replace("_", "")
		if literal == "true" or literal == "false":
			found[m.get_string(1)] = literal == "true"
		elif integer.search(literal):
			found[m.get_string(1)] = int(digits.rstrip("uUlL"))
		elif digits.length() > 0 and digits != "-" and real.search(literal) and digits.rstrip("fFdDmM").is_valid_float():
			found[m.get_string(1)] = float(digits.rstrip("fFdDmM"))
		elif text.search(literal):
			found[m.get_string(1)] = text.search(literal).get_string(1)
		else:
			found[m.get_string(1)] = func() -> String: return literal
	var suffixed := RegEx.create_from_string("(?<![\\w.])([0-9][0-9_]*(?:\\.[0-9][0-9_]*)?(?:[eE][+-]?[0-9]+)?)([fFdDmM]|[uUlL]+)?(?![\\w.])")
	var progress := true
	while progress:
		progress = false
		var names: Array[String] = []
		var values := []
		for key in found:
			if not found[key] is Callable:
				names.append(key)
				values.append(found[key])
		for key in found:
			if not found[key] is Callable:
				continue
			var source_text: String = found[key].call()
			var converted := ""
			var at := 0
			for n in suffixed.search_all(source_text):
				var number := n.get_string(1).replace("_", "")
				if n.get_string(2) != "" and n.get_string(2)[0] in "fFdDmM" and not "." in number and not "e" in number.to_lower():
					number += ".0"
				converted += source_text.substr(at, n.get_start() - at) + number
				at = n.get_end()
			converted += source_text.substr(at)
			var expression := Expression.new()
			if expression.parse(converted, PackedStringArray(names)) != OK:
				continue
			var result = expression.execute(values, null, false)
			if expression.has_execute_failed() or not typeof(result) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
				continue
			found[key] = result
			progress = true
			break
	return found
