class_name Story
extends RefCounted
## One playthrough of the story: the node it is at, the flags and the choices taken so far (the history). Engine-light,
## so tests play whole stories without a scene; the story scene only shows it.

## The story moved to a node (also at the start).
signal node_entered(node_id: String)
## A flag changed value through a choice's effects.
signal flag_changed(flag: String, before: int, after: int)
## The story reached an ending node.
signal ended(ending_id: String)

var graph: StoryGraph
var node_id := ""
## Flag id -> value; every flag of the graph is present, 0 until a choice changes it.
var flags := {}
## The ids of the choices taken, in order.
var history := PackedStringArray()


func _init(story_graph: StoryGraph) -> void:
	graph = story_graph
	reset()


## Back to the first node with every flag at 0 and no history.
func reset() -> void:
	node_id = graph.start
	flags = {}
	for flag: String in graph.flags:
		flags[flag] = 0
	history = PackedStringArray()


func current() -> Dictionary:
	return graph.node(node_id)


## The ending this story is at, or "".
func ending() -> String:
	return graph.ending_at(node_id)


func is_over() -> bool:
	return not ending().is_empty()


## The choices the player is offered now: those out of this node whose needs hold. None at an ending.
func available() -> Array:
	var out := []
	if is_over():
		return out
	for choice: Dictionary in graph.choices_from(node_id):
		if is_open(choice):
			out.append(choice)
	return out


func is_open(choice: Dictionary) -> bool:
	# A choice into a node the story does not have would leave the player with nothing: never offer it.
	if not graph.has_node(choice.to):
		return false
	return Conditions.holds(choice.needs, flags)


func can_choose(choice_id: String) -> bool:
	for choice: Dictionary in available():
		if choice.id == choice_id:
			return true
	return false


## Takes a choice offered now: its effects (raise, then set, then clear), the history, then the node it leads to.
## False when the choice is not offered.
func choose(choice_id: String) -> bool:
	if not can_choose(choice_id):
		return false
	var choice := graph.choice(choice_id)
	for flag: String in choice.raise:
		_change(flag, int(flags.get(flag, 0)) + 1)
	for flag: String in choice.set:
		_change(flag, 1)
	for flag: String in choice.clear:
		_change(flag, 0)
	history.append(choice_id)
	node_id = choice.to
	node_entered.emit(node_id)
	if is_over():
		ended.emit(ending())
	return true


func _change(flag: String, value: int) -> void:
	var before := int(flags.get(flag, 0))
	flags[flag] = value
	if before != value:
		flag_changed.emit(flag, before, value)


func to_dict() -> Dictionary:
	return {
		"node": node_id,
		"flags": flags.duplicate(),
		"history": Array(history),
	}


## A story carried on from to_dict(); flags the save lacks start at 0, and a node the story no longer has is the start.
static func from_dict(story_graph: StoryGraph, data: Dictionary) -> Story:
	var story := Story.new(story_graph)
	var saved_node := str(data.get("node", story_graph.start))
	story.node_id = saved_node if story_graph.has_node(saved_node) else story_graph.start
	var saved_flags: Variant = data.get("flags", {})
	if typeof(saved_flags) == TYPE_DICTIONARY:
		for flag: Variant in saved_flags:
			story.flags[str(flag)] = int(saved_flags[flag])
	var saved_history: Variant = data.get("history", [])
	if typeof(saved_history) == TYPE_ARRAY:
		for id: Variant in saved_history:
			story.history.append(str(id))
	return story


## A new story with these choices taken in order; it stops at the first one that is not offered.
static func replay(story_graph: StoryGraph, choice_ids: Array) -> Story:
	var story := Story.new(story_graph)
	for id: Variant in choice_ids:
		if not story.choose(str(id)):
			break
	return story
