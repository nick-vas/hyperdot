extends Control
## The story on screen: the line of the node the story is at, typed out, then the choices it offers. At an ending, its
## title and a way to cross again.
## The story itself lives in Story; this node only paces it. A line appears a few characters a tick and a choice taken
## turns the page for a moment before the story moves on, all in _physics_process at 60 ticks.

## Characters of a line typed out per tick.
const REVEAL_PER_TICK := 3
## Ticks between taking a choice and the next line.
const TURN_TICKS := 12
const CHOICE_FONT_SIZE := 22
const CHAPTER_KEYS := ["", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3"]
const SPEAKER_KEYS := {"narrator": "SPEAKER_NARRATOR", "stranger": "SPEAKER_STRANGER"}

var graph: StoryGraph
var story: Story
## "reading" (the line is being typed), "choosing", "turning" (a choice taken) or "ended".
var state := "reading"
var node: String:
	get:
		return story.node_id if story else ""
var chapter: int:
	get:
		return int(story.current().get("chapter", 0)) if story else 0

var _wait := 0
var _shown := 0
var _pending := ""

@onready var _backdrop: Control = $Backdrop
@onready var _panel: Control = $Panel
@onready var _speaker: Label = $Panel/Speaker
@onready var _text: Label = $Panel/Text
@onready var _choices: VBoxContainer = $Choices
@onready var _chapter_label: Label = $HUD/ChapterLabel


func _ready() -> void:
	if graph == null:
		graph = StoryGraph.from_files()
	_panel.gui_input.connect(_on_panel_input)
	start_new()


## A new story from the first node.
func start_new() -> void:
	story = Story.new(graph)
	story.node_entered.connect(_on_node_entered)
	print("[Story] begin at %s" % story.node_id)
	_show_node()


func _show_node() -> void:
	print("[Story] node %s" % story.node_id)
	_clear_choices()
	_shown = 0
	state = "reading"
	var current := story.current()
	_speaker.text = tr(SPEAKER_KEYS.get(current.get("speaker", ""), "SPEAKER_NARRATOR"))
	_text.text = tr(str(current.get("text", "")))
	_text.visible_characters = 0
	_chapter_label.text = tr(CHAPTER_KEYS[clampi(chapter, 0, CHAPTER_KEYS.size() - 1)])
	_backdrop.chapter = chapter


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


## Takes a choice the story offers now; false when it is not offered or the choices are not shown yet.
func choose_id(choice_id: String) -> bool:
	if state != "choosing" or not story.can_choose(choice_id):
		return false
	print("[Story] choice %s" % choice_id)
	for button: Button in _choices.get_children():
		button.disabled = true
	_pending = choice_id
	_wait = TURN_TICKS
	state = "turning"
	return true


func _physics_process(_delta: float) -> void:
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


func _on_revealed() -> void:
	if story.is_over():
		print("[Story] ending %s" % story.ending())
		_speaker.text = tr(str(graph.endings[story.ending()].title))
		_add_button("Again", tr("ENDING_AGAIN"), start_new)
		state = "ended"
		return
	for choice: Dictionary in story.available():
		_add_button("Choice%d" % _choices.get_child_count(), tr(choice.text), choose_id.bind(choice.id))
	state = "choosing"


func _add_button(button_name: String, text: String, action: Callable) -> void:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(0, 88)
	button.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = text
	button.pressed.connect(action)
	_choices.add_child(button)


func _clear_choices() -> void:
	for button in _choices.get_children():
		_choices.remove_child(button)
		button.queue_free()


func _on_node_entered(_node_id: String) -> void:
	_show_node()
