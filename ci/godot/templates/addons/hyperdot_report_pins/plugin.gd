# Report pins: the bug reports bug_report.gd saved (report_pins.gd finds them), drawn on the scene they came from in
# the 2D and 3D editors, a numbered dot where the player stood and a ring where the camera was, and listed in a
# "Reports" dock (a report's text, build and seed in its tooltip; Reload reads the folders again). Enable it in
# Project Settings > Plugins after copying this folder to res://addons/.
@tool
extends EditorPlugin

const Pins = preload("report_pins.gd")
const PIN := Color(1.0, 0.35, 0.2)
const VIEW := Color(0.3, 0.8, 1.0)

var _reports := []
var _dock: VBoxContainer
var _list: ItemList


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Reports"
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_refresh)
	_dock.add_child(reload)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(index: int) -> void: print(Pins.details(_reports[index])))
	_dock.add_child(_list)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	scene_changed.connect(_on_scene_changed)
	set_force_draw_over_forwarding_enabled()
	_refresh()


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _on_scene_changed(_root: Node) -> void:
	_refresh()


func _refresh() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var path := root.scene_file_path if root else ""
	_reports = Pins.for_scene(Pins.load_reports(), path)
	_list.clear()
	for i in _reports.size():
		_list.add_item(Pins.label(_reports[i], i))
		_list.set_item_tooltip(i, Pins.details(_reports[i]))
	print_verbose("report pins: %d report(s) for %s" % [_reports.size(), path if path else "no scene"])
	update_overlays()


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	for i in _reports.size():
		var view = Pins.camera_transform(_reports[i])
		if view is Transform3D:
			var at = Pins.screen_point(camera, view.origin)
			if at != null:
				overlay.draw_arc(at, 9.0, 0.0, TAU, 24, VIEW, 2.0)
		var player = Pins.vector(_reports[i].get("player"))
		if player is Vector3:
			var at = Pins.screen_point(camera, player)
			if at != null:
				_draw_pin(overlay, at, i)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	var to_screen := EditorInterface.get_editor_viewport_2d().global_canvas_transform
	for i in _reports.size():
		var camera = _reports[i].get("camera")
		if camera is Dictionary and Pins.vector(camera.get("position")) is Vector2:
			overlay.draw_arc(to_screen * Pins.vector(camera["position"]), 9.0, 0.0, TAU, 24, VIEW, 2.0)
		var player = Pins.vector(_reports[i].get("player"))
		if player is Vector2:
			_draw_pin(overlay, to_screen * player, i)


func _draw_pin(overlay: Control, at: Vector2, index: int) -> void:
	overlay.draw_circle(at, 7.0, PIN)
	var font := overlay.get_theme_default_font()
	overlay.draw_string(font, at + Vector2(10, 5), Pins.label(_reports[index], index), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
