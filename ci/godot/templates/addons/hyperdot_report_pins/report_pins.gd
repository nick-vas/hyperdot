# What the report pins add-on (plugin.gd) shows, without the editor: the reports bug_report.gd saved, those of one
# scene, and where each lands on a camera's screen. res://reports is for reports shared in the repository (a tester's,
# a CI run's), user://reports for the ones this machine's game wrote; the editor's user:// is the game's.
extends RefCounted

const DIRS := ["res://reports", "user://reports"]
const LABEL_LENGTH := 48


# Every report in the folders, oldest first, each with "file" (its path) added: once, from the first folder, when a
# report was copied from user:// to res://reports to share it. A file that is not a report is skipped.
static func load_reports(dirs: Array = DIRS) -> Array:
	var reports := []
	var seen := {}
	for dir in dirs:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for name in DirAccess.get_files_at(dir):
			if not name.ends_with(".json"):
				continue
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(str(dir).path_join(name))) != OK:
				continue
			var data = json.data
			if data is Dictionary and str(data.get("schema", "")).begins_with("hyperdot-bug-report/"):
				var key := "%s|%s|%s" % [data.get("time", ""), data.get("scene", ""), data.get("text", "")]
				if seen.has(key):
					continue
				seen[key] = true
				data["file"] = str(dir).path_join(name)
				reports.append(data)
	reports.sort_custom(func(a, b): return str(a.get("time", "")) < str(b.get("time", "")))
	return reports


static func for_scene(reports: Array, scene_path: String) -> Array:
	return reports.filter(func(r): return scene_path != "" and str(r.get("scene", "")) == scene_path)


# A saved position as a Vector3 or Vector2, or null.
static func vector(value) -> Variant:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return null


# The report's Camera3D transform, or null (a 2D camera, or none saved).
static func camera_transform(report: Dictionary) -> Variant:
	var camera = report.get("camera")
	if not camera is Dictionary or not camera.get("basis") is Array or camera["basis"].size() != 9:
		return null
	var origin = vector(camera.get("position"))
	if not origin is Vector3:
		return null
	var b: Array = camera["basis"]
	return Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])), origin)


# Where a point is on the camera's screen, or null when it is behind the camera.
static func screen_point(camera: Camera3D, point: Vector3) -> Variant:
	if camera == null or camera.is_position_behind(point):
		return null
	return camera.unproject_position(point)


static func label(report: Dictionary, index: int) -> String:
	var text := str(report.get("text", "")).strip_edges().replace("\n", " ")
	if text.length() > LABEL_LENGTH:
		text = text.substr(0, LABEL_LENGTH - 3) + "..."
	return "%d  %s" % [index + 1, text]


# The rest of the report, for a tooltip: when, the build, and the command line that replays its seed.
static func details(report: Dictionary) -> String:
	var lines := [str(report.get("text", ""))]
	lines.append("%s, commit %s, Godot %s" % [report.get("time", "?"), report.get("commit", "?"), report.get("engine", "?")])
	lines.append("seed %s: run the game with --seed=%s" % [report.get("seed", 0), report.get("seed", 0)])
	if report.has("screenshot"):
		lines.append("screenshot " + str(report["file"]).get_base_dir().path_join(str(report["screenshot"])))
	lines.append(str(report.get("file", "")))
	return "\n".join(lines)
