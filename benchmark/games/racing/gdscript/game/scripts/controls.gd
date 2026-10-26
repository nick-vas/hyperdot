class_name Controls
extends RefCounted
## The keys the player has rebound. Only keyboard bindings change: each action keeps its controller bindings, so a
## rebind never takes the gamepad away. Keys are kept by their physical position (WASD stays under the same fingers on
## another layout) and saved as their names, {"accelerate": "W"}; an unknown action or key name changes nothing.

const ACTIONS: Array[String] = ["accelerate", "brake", "steer_left", "steer_right"]


## The keyboard key of an action, 0 when it has none.
static func key_of(action: String) -> Key:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return KEY_NONE


static func label(action: String) -> String:
	var key := key_of(action)
	return OS.get_keycode_string(key) if key != KEY_NONE else "-"


## Binds an action to a key in place of its keyboard binding; false for an action that is not rebindable.
static func rebind(action: String, key: Key) -> bool:
	if not ACTIONS.has(action) or key == KEY_NONE:
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var bound := InputEventKey.new()
	bound.physical_keycode = key
	InputMap.action_add_event(action, bound)
	return true


static func to_dict() -> Dictionary:
	var out := {}
	for action in ACTIONS:
		var key := key_of(action)
		if key != KEY_NONE:
			out[action] = OS.get_keycode_string(key)
	return out


## Applies saved bindings over the current ones.
static func apply(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	for action in ACTIONS:
		if data.has(action):
			var key := OS.find_keycode_from_string(str(data[action]))
			if key != KEY_NONE:
				rebind(action, key)


## Back to the project's bindings.
static func reset() -> void:
	InputMap.load_from_project_settings()
