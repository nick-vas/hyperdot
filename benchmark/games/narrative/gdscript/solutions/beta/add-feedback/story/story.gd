extends Control
## The story on screen: the line of the node the story is at, typed out, then the choices it offers; history, pause and
## the ending panel. Main starts it with setup(); on its own (a flow, a test, the editor) it reads the command line and
## the data itself.
## The story itself lives in Story; this node only paces it. A line appears a few characters a tick, a choice taken
## turns the page for a moment before the story moves on, and the bot thinks before each choice. Everything runs in
## _physics_process at 60 ticks, so a bot run replays the same on every machine.

## A node was shown: Main keeps the story in the save, so Continue carries on from here.
signal checkpoint(data: Dictionary)
## The story reached an ending: Main records it.
signal ending_found(ending_id: String)
## A bot run is over: every ending it could reach was reached.
signal finished
signal menu_requested

## Characters of a line typed out per tick.
const REVEAL_PER_TICK := 3
## Ticks between taking a choice and the next line: longer than the juice window, so a choice's sound never stands in
## for the feedback of what the choice causes.
const TURN_TICKS := 12
## Ticks the bot reads the choices before it takes one.
const THINK_TICKS := 20
## Ticks an ending's line stays before the ending panel opens.
const ENDING_PANEL_TICKS := 30
## How long a bot run shows the ending panel before the next story.
const AUTOPLAY_NEXT_TICKS := 40
const CHOICE_FONT_SIZE := 22
const CHAPTER_KEYS := ["", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3"]
const SPEAKER_KEYS := {"narrator": "SPEAKER_NARRATOR", "stranger": "SPEAKER_STRANGER"}

var graph: StoryGraph
var options: LaunchOptions
var story: Story
## The ids of the endings found so far (the save's list, shared with Main).
var found := []
## "reading" (the line is being typed), "choosing", "turning" (a choice taken), "ending" (an ending's line shown),
## "ended" (the ending panel is open) or "done" (a bot run is over).
var state := "reading"
## How many times the choices were worked out, for the performance test.
var choice_checks := 0
var node: String:
	get:
		return story.node_id if story else ""
var chapter: int:
	get:
		return int(story.current().get("chapter", 0)) if story else 0

var _saved := {}
var _ticks := 0
var _wait := 0
var _shown := 0
var _pending := ""
var _flash := 0.0
## The bot's way to its next ending, and the endings it reached or gave up on in this run.
var _plan := PackedStringArray()
var _target := ""
var _bot_reached := []
var _bot_missed := []

@onready var _backdrop: Control = $Backdrop
@onready var _flash_rect: ColorRect = $Flash
@onready var _panel: Control = $Panel
@onready var _speaker: Label = $Panel/Speaker
@onready var _text: Label = $Panel/Text
@onready var _choices: VBoxContainer = $Choices
@onready var _chapter_label: Label = $HUD/ChapterLabel
@onready var _history_button: Button = $HUD/HistoryButton
@onready var _pause_button: Button = $HUD/PauseButton
@onready var _history: CanvasLayer = $History
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _ending_menu: CanvasLayer = $EndingMenu
@onready var _sfx_choice: AudioStreamPlayer = $SfxChoice
@onready var _sfx_trust: AudioStreamPlayer = $SfxTrust
@onready var _sfx_ending: AudioStreamPlayer = $SfxEnding


## found_endings: the save's list of endings found; saved: a story from the save to carry on instead of a new one.
func setup(story_graph: StoryGraph, game_options: LaunchOptions, found_endings: Array, saved := {}) -> void:
	graph = story_graph
	options = game_options
	found = found_endings
	_saved = saved


func _ready() -> void:
	if options == null:
		options = LaunchOptions.from_command_line()
	if graph == null:
		graph = StoryGraph.from_files()
	_history_button.pressed.connect(open_history)
	_pause_button.pressed.connect(_pause_menu.open)
	_pause_menu.quit_pressed.connect(menu_requested.emit)
	_ending_menu.again_pressed.connect(start_new)
	_ending_menu.menu_pressed.connect(menu_requested.emit)
	_panel.gui_input.connect(_on_panel_input)
	if _saved.is_empty():
		start_new()
	else:
		resume(_saved)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


## A new story from the first node.
func start_new() -> void:
	_begin(Story.new(graph))


## Carries on a story kept in the save (Story.to_dict()).
func resume(data: Dictionary) -> void:
	_begin(Story.from_dict(graph, data))


func _begin(next: Story) -> void:
	story = next
	story.node_entered.connect(_on_node_entered)
	story.flag_changed.connect(_on_flag_changed)
	story.ended.connect(_on_ended)
	_ending_menu.close()
	_history.close()
	print("[Story] begin at %s" % story.node_id)
	if options.autoplay:
		_plan_next()
	_show_node()


## Shows the node the story is at: its speaker and chapter at once, its line typed out from the start.
func _show_node() -> void:
	print("[Story] node %s" % story.node_id)
	_clear_choices()
	_shown = 0
	state = "reading"
	_refresh_text()
	if not story.is_over():
		checkpoint.emit(story.to_dict())


func _refresh_text() -> void:
	_history_button.text = tr("HUD_HISTORY")
	_pause_button.text = tr("HUD_PAUSE")
	if story == null:
		return
	var current := story.current()
	_speaker.text = tr(SPEAKER_KEYS.get(current.get("speaker", ""), "SPEAKER_NARRATOR"))
	_text.text = tr(str(current.get("text", "")))
	_text.visible_characters = -1 if state != "reading" else _shown
	_chapter_label.text = tr(CHAPTER_KEYS[clampi(chapter, 0, CHAPTER_KEYS.size() - 1)])
	_backdrop.chapter = chapter
	for button: Button in _choices.get_children():
		button.text = tr(str(graph.choice(str(button.get_meta("choice"))).get("text", "")))


## The whole line at once (a click on the text, or ui_accept).
func reveal_all() -> void:
	if state == "reading":
		_shown = _text.text.length()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		reveal_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and state == "reading":
		reveal_all()
		get_viewport().set_input_as_handled()


## Takes the choice of this index among those shown.
func choose(index: int) -> bool:
	if index < 0 or index >= _choices.get_child_count():
		return false
	return choose_id(str(_choices.get_child(index).get_meta("choice")))


## Takes a choice the story offers now; false when it is not offered or the choices are not shown yet.
func choose_id(choice_id: String) -> bool:
	if state != "choosing" or not story.can_choose(choice_id):
		return false
	print("[Story] choice %s" % choice_id)
	_event("choice_made")
	_play(_sfx_choice)
	for button: Button in _choices.get_children():
		button.disabled = true
	_pending = choice_id
	_wait = TURN_TICKS
	state = "turning"
	return true


func _physics_process(delta: float) -> void:
	_ticks += 1
	_update_effects(delta)
	match state:
		"reading":
			var total := _text.text.length()
			if _shown < total:
				_shown = mini(_shown + REVEAL_PER_TICK, total)
				_text.visible_characters = _shown
			else:
				_text.visible_characters = -1
				_on_revealed()
		"turning":
			_wait -= 1
			if _wait <= 0:
				story.choose(_pending)
		"choosing":
			if options.autoplay:
				_wait -= 1
				if _wait <= 0:
					_bot_choose()
		"ending":
			_wait -= 1
			if _wait <= 0:
				_ending_menu.open(str(graph.endings[story.ending()].title), found.size(), graph.ending_ids.size())
				state = "ended"
				_wait = AUTOPLAY_NEXT_TICKS
		"ended":
			if options.autoplay:
				_wait -= 1
				if _wait <= 0:
					_bot_next()


func _on_revealed() -> void:
	if story.is_over():
		state = "ending"
		_wait = ENDING_PANEL_TICKS
		return
	_show_choices()
	state = "choosing"
	_wait = THINK_TICKS


## One button per choice the story offers, Choice0 first, worked out once per line.
func _show_choices() -> void:
	choice_checks += 1
	_clear_choices()
	for choice: Dictionary in story.available():
		var button := Button.new()
		button.name = "Choice%d" % _choices.get_child_count()
		button.custom_minimum_size = Vector2(0, 88)
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.set_meta("choice", choice.id)
		button.text = tr(choice.text)
		button.pressed.connect(choose_id.bind(choice.id))
		_choices.add_child(button)
	if _choices.get_child_count() > 0 and not options.autoplay:
		_choices.get_child(0).grab_focus.call_deferred()


func _clear_choices() -> void:
	for button in _choices.get_children():
		_choices.remove_child(button)
		button.queue_free()


func _on_node_entered(_node_id: String) -> void:
	_show_node()


func _on_flag_changed(flag: String, before: int, after: int) -> void:
	if flag == "trust" and after > before:
		_event("trust_gained")
		_backdrop.glow = 1.0
		_feedback("glow")
		_play(_sfx_trust)


func _on_ended(ending_id: String) -> void:
	print("[Story] ending %s" % ending_id)
	if not found.has(ending_id):
		found.append(ending_id)
	_event("ending_reached")
	_flash_screen(Color(1.0, 0.92, 0.7, 0.45))
	_play(_sfx_ending)
	ending_found.emit(ending_id)


## The lines so far, for the history panel: each node's line and, after it, the choice taken there.
func history_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var at := graph.start
	lines.append(tr(str(graph.node(at).get("text", ""))))
	for id in story.history:
		var choice := graph.choice(id)
		lines.append(tr("HISTORY_CHOICE") % tr(str(choice.get("text", ""))))
		at = str(choice.get("to", ""))
		lines.append(tr(str(graph.node(at).get("text", ""))))
	return lines


func open_history() -> void:
	_history.open(history_lines())


# ---- The bot (--autoplay): every ending in turn, by the shortest way StoryCheck finds ----

func _plan_next() -> void:
	_plan = PackedStringArray()
	_target = ""
	for id: String in graph.ending_ids:
		if _bot_reached.has(id) or _bot_missed.has(id):
			continue
		var path := StoryCheck.path_to(graph, id, story)
		if path.is_empty():
			print("[Run] no way to ending %s" % id)
			_bot_missed.append(id)
			continue
		_target = id
		_plan = path
		return


func _bot_choose() -> void:
	if _plan.is_empty():
		_plan_next()
	if _plan.is_empty():
		_bot_finish()
		return
	var id := _plan[0]
	_plan.remove_at(0)
	if not choose_id(id):
		push_error("The bot's choice %s is not offered at %s" % [id, story.node_id])
		_bot_finish()


func _bot_next() -> void:
	if not _bot_reached.has(story.ending()):
		_bot_reached.append(story.ending())
	if _bot_reached.size() + _bot_missed.size() < graph.ending_ids.size():
		start_new()
		if not _target.is_empty():
			return
	_bot_finish()


func _bot_finish() -> void:
	print("[Run] endings found %d of %d" % [_bot_reached.size(), graph.ending_ids.size()])
	if _bot_reached.size() == graph.ending_ids.size():
		print("[Run] every ending")
	state = "done"
	finished.emit()
	# On its own (a flow, or the story scene run alone) nobody listens; a bot run then ends here.
	if finished.get_connections().is_empty():
		get_tree().quit()


# Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
func game_ms() -> float:
	return _ticks * 1000.0 / Engine.physics_ticks_per_second


func _event(event_name: String) -> void:
	print("[juice] event %s %.1f" % [event_name, game_ms()])


func _feedback(kind: String) -> void:
	print("[juice] feedback %s %.1f" % [kind, game_ms()])


func _flash_screen(color: Color) -> void:
	_flash = color.a
	_flash_rect.color = color
	_feedback("flash")


func _play(player: AudioStreamPlayer) -> void:
	player.play()
	_feedback("sfx")


func _update_effects(delta: float) -> void:
	_flash = maxf(_flash - delta * 1.5, 0.0)
	_flash_rect.color.a = _flash
	_backdrop.glow = maxf(_backdrop.glow - delta * 1.2, 0.0)
