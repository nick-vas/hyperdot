# A bug report as godot-automation-hooks asks for ("A feedback key"): one typed line saves the scene, where the player and
# the camera were, the seed and the build, so the report pins add-on beside this file shows it on the level in the
# editor. From the game's feedback key:
#   const BugReport = preload("res://addons/hyperdot_report_pins/bug_report.gd")
#   BugReport.save(text, get_tree().current_scene, $Player, get_viewport().get_camera_3d(), run_seed, build_commit)
# 2D works the same with a Node2D and a Camera2D. It writes user://reports/<UTC time>.json, and a .png of the screen
# unless screenshot is false or the renderer gives no image (headless), and returns the JSON's path ("" if it failed).
extends RefCounted

const SCHEMA := "hyperdot-bug-report/1"
const DIR := "user://reports"


static func save(text: String, scene: Node, player: Node, camera: Node, run_seed := 0, commit := "", dir := DIR, screenshot := true) -> String:
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		push_error("bug_report.gd: cannot make %s" % dir)
		return ""
	# The time to the millisecond, and -2, -3 ... when two reports fall in the same one.
	var now := Time.get_unix_time_from_system()
	var stamp := "%s-%03d" % [Time.get_datetime_string_from_unix_time(int(now)).replace(":", "-"), int(fmod(now, 1.0) * 1000.0)]
	var name := stamp
	var count := 1
	while FileAccess.file_exists(dir.path_join(name + ".json")):
		count += 1
		name = "%s-%d" % [stamp, count]
	var report := {
		"schema": SCHEMA,
		"time": Time.get_datetime_string_from_unix_time(int(now)) + "Z",
		"text": text,
		"scene": scene.scene_file_path if scene else "",
		"player": _position(player),
		"camera": _camera(camera),
		"seed": run_seed,
		"commit": commit,
		"engine": Engine.get_version_info().string,
	}
	if screenshot and scene and scene.get_viewport() and DisplayServer.get_name() != "headless":
		var texture := scene.get_viewport().get_texture()
		var image := texture.get_image() if texture else null
		if image and image.save_png(dir.path_join(name + ".png")) == OK:
			report["screenshot"] = name + ".png"
	var path := dir.path_join(name + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("bug_report.gd: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	file.store_string(JSON.stringify(report, "  "))
	return path


static func _position(node: Node) -> Variant:
	if node is Node3D:
		var p: Vector3 = node.global_position
		return [p.x, p.y, p.z]
	if node is Node2D:
		var q: Vector2 = node.global_position
		return [q.x, q.y]
	return null


# A Camera3D as its position and basis (its columns x, y, z), a Camera2D as its position and zoom.
static func _camera(node: Node) -> Variant:
	if node is Camera3D:
		var t: Transform3D = node.global_transform
		return {"position": [t.origin.x, t.origin.y, t.origin.z],
			"basis": [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z]}
	if node is Camera2D:
		var c: Camera2D = node
		return {"position": [c.global_position.x, c.global_position.y], "zoom": [c.zoom.x, c.zoom.y]}
	return null
