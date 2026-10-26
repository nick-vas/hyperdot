class_name StoryCheck
extends RefCounted
## What the data runner cannot see in the story: every node and ending reachable by some order of choices, no state
## where no choice is open short of an ending, and every flag both written and read. The search plays every order of
## choices from the start (flags capped just above the largest number any needs compare with, so loops end), and finds
## the bot its way to each ending.

const MAX_STATES := 20000


## Everything wrong with a story, as sentences; empty when it is sound.
static func problems(graph: StoryGraph) -> PackedStringArray:
	var out := PackedStringArray()
	if graph.start.is_empty():
		out.append("the story has no nodes")
		return out
	for id: String in graph.choices:
		var choice: Dictionary = graph.choices[id]
		if not graph.has_node(choice.from):
			out.append("choice '%s' starts at '%s', which is no node" % [id, choice.from])
		if not graph.has_node(choice.to):
			out.append("choice '%s' leads to '%s', which is no node" % [id, choice.to])
	for id: String in graph.ending_ids:
		var at: String = graph.endings[id].node
		if not graph.has_node(at):
			out.append("ending '%s' is at '%s', which is no node" % [id, at])
		elif not graph.choices_from(at).is_empty():
			out.append("ending '%s' at '%s' has choices out of it" % [id, at])
	for id: String in graph.nodes:
		if graph.ending_at(id).is_empty() and graph.choices_from(id).is_empty():
			out.append("node '%s' is no ending and has no choice out of it" % id)
	var read := {}
	var written := {}
	for id: String in graph.choices:
		var choice: Dictionary = graph.choices[id]
		for flag in Conditions.keys(choice.needs):
			read[flag] = id
		for flag: String in Array(choice.raise) + Array(choice.set) + Array(choice.clear):
			written[flag] = id
	for flag: String in read.keys() + written.keys():
		if not graph.flags.has(flag):
			out.append("flag '%s' of choice '%s' is not in flags.json" % [flag, read.get(flag, written.get(flag))])
	for flag: String in graph.flags:
		if not written.has(flag):
			out.append("flag '%s' is never set" % flag)
		if not read.has(flag):
			out.append("flag '%s' is never read" % flag)
	var found := search(graph)
	for id: String in graph.nodes:
		if not found.nodes.has(id):
			out.append("node '%s' cannot be reached" % id)
	for id: String in graph.ending_ids:
		if not found.endings.has(id):
			out.append("ending '%s' cannot be reached" % id)
	for at: String in found.dead_ends:
		out.append("a story can get stuck at '%s' (%s): no choice is open" % [at, found.dead_ends[at]])
	if found.truncated:
		out.append("the story has more than %d states" % MAX_STATES)
	return out


## Every state reachable from a story (a new one when null): { "nodes": node id -> true, "endings": ending id -> true,
## "paths": ending id -> the choice ids of a shortest way there, "dead_ends": node id -> its flags, "truncated" }.
static func search(graph: StoryGraph, from: Story = null) -> Dictionary:
	var cap := _cap(graph)
	var first := Story.new(graph) if from == null else Story.from_dict(graph, from.to_dict())
	_clamp(first, cap)
	var result := {"nodes": {}, "endings": {}, "paths": {}, "dead_ends": {}, "truncated": false}
	var seen := {_key(first): true}
	var queue: Array = [[first, PackedStringArray()]]
	var head := 0
	while head < queue.size():
		var story: Story = queue[head][0]
		var path: PackedStringArray = queue[head][1]
		head += 1
		result.nodes[story.node_id] = true
		if story.is_over():
			if not result.endings.has(story.ending()):
				result.endings[story.ending()] = true
				result.paths[story.ending()] = path
			continue
		var open := story.available()
		if open.is_empty():
			result.dead_ends[story.node_id] = JSON.stringify(story.flags)
			continue
		for choice: Dictionary in open:
			var next := Story.from_dict(graph, story.to_dict())
			next.choose(choice.id)
			_clamp(next, cap)
			var key := _key(next)
			if seen.has(key):
				continue
			if seen.size() >= MAX_STATES:
				result.truncated = true
				return result
			seen[key] = true
			var next_path := path.duplicate()
			next_path.append(choice.id)
			queue.append([next, next_path])
	return result


## The choices of a shortest way from a story (a new one when null) to an ending; empty when there is none.
static func path_to(graph: StoryGraph, ending_id: String, from: Story = null) -> PackedStringArray:
	return search(graph, from).paths.get(ending_id, PackedStringArray())


## One above the largest number any needs compare with: values above it behave alike.
static func _cap(graph: StoryGraph) -> int:
	var cap := 1
	for id: String in graph.choices:
		for criterion in Conditions.parse(graph.choices[id].needs):
			cap = maxi(cap, int(criterion.value) + 1)
	return cap


static func _clamp(story: Story, cap: int) -> void:
	for flag: String in story.flags:
		story.flags[flag] = mini(int(story.flags[flag]), cap)


## A state: the node, the flags, and which once-only choices are spent.
static func _key(story: Story) -> String:
	var spent := PackedStringArray()
	for id in story.history:
		if story.graph.choice(id).get("once", false) and not spent.has(id):
			spent.append(id)
	spent.sort()
	var names := story.flags.keys()
	names.sort()
	var values := PackedStringArray()
	for flag: String in names:
		values.append("%s=%d" % [flag, int(story.flags[flag])])
	return "%s|%s|%s" % [story.node_id, ",".join(values), ",".join(spent)]
