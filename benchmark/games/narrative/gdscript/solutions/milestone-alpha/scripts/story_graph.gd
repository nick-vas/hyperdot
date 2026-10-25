class_name StoryGraph
extends RefCounted
## The story as data: nodes (a line of text and who says it), choices (from a node to a node, with needs and effects),
## flags and endings, read from data/*.json. Read-only once loaded; a playthrough's state lives in Story.

const DATA_DIR := "res://data"

## Node id -> { "id", "chapter", "speaker", "text" }.
var nodes := {}
## Choice id -> { "id", "from", "to", "text", "needs", "raise", "set", "clear", "once" }.
var choices := {}
## Flag id -> { "id", "kind" }: "count" (raised one at a time) or "switch" (set and cleared).
var flags := {}
## Ending ids in file order, and ending id -> { "id", "node", "title" }.
var ending_ids := PackedStringArray()
var endings := {}
## The first node of nodes.json: where every story begins.
var start := ""

var _from := {}
var _ending_at := {}


static func from_files(dir := DATA_DIR) -> StoryGraph:
	return StoryGraph.from_data(_read(dir + "/nodes.json"), _read(dir + "/choices.json"), _read(dir + "/flags.json"), _read(dir + "/endings.json"))


static func from_data(node_rows: Array, choice_rows: Array, flag_rows: Array, ending_rows: Array) -> StoryGraph:
	var graph := StoryGraph.new()
	for row: Dictionary in node_rows:
		var id := str(row.id)
		graph.nodes[id] = {"id": id, "chapter": int(row.get("chapter", 1)), "speaker": str(row.get("speaker", "narrator")), "text": str(row.get("text", ""))}
		if graph.start.is_empty():
			graph.start = id
	for row: Dictionary in flag_rows:
		graph.flags[str(row.id)] = {"id": str(row.id), "kind": str(row.get("kind", "switch"))}
	for row: Dictionary in choice_rows:
		var choice := {
			"id": str(row.id), "from": str(row.from), "to": str(row.to), "text": str(row.get("text", "")),
			"needs": str(row.get("needs", "")), "once": bool(row.get("once", false)),
			"raise": _names(row.get("raise", [])), "set": _names(row.get("set", [])), "clear": _names(row.get("clear", [])),
		}
		graph.choices[choice.id] = choice
		if not graph._from.has(choice.from):
			graph._from[choice.from] = []
		graph._from[choice.from].append(choice)
	for row: Dictionary in ending_rows:
		var ending := {"id": str(row.id), "node": str(row.node), "title": str(row.get("title", ""))}
		graph.ending_ids.append(ending.id)
		graph.endings[ending.id] = ending
		graph._ending_at[ending.node] = ending.id
	return graph


func has_node(id: String) -> bool:
	return nodes.has(id)


## A node, or an empty dictionary when there is none.
func node(id: String) -> Dictionary:
	return nodes.get(id, {})


func choice(id: String) -> Dictionary:
	return choices.get(id, {})


## The choices out of a node, in file order.
func choices_from(node_id: String) -> Array:
	return _from.get(node_id, [])


## The ending a node is, or "" when it is not one.
func ending_at(node_id: String) -> String:
	return _ending_at.get(node_id, "")


static func _names(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(value) == TYPE_ARRAY:
		for item: Variant in value:
			out.append(str(item))
	return out


static func _read(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("StoryGraph: %s is missing" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("StoryGraph: %s is not a JSON array" % path)
		return []
	return parsed
