namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// The story on screen: the line of the node the story is at, typed out, then the choices it offers. At an ending, its
/// title and a way to cross again.
/// The story itself lives in Story; this node only paces it. A line appears a few characters a tick and a choice taken
/// turns the page for a moment before the story moves on, all in _PhysicsProcess at 60 ticks.
/// </summary>
/// <remarks>
/// <c>story</c>, <c>graph</c>, <c>node</c>, <c>chapter</c>, <c>state</c> and the methods <c>start_new</c>,
/// <c>reveal_all</c> and <c>choose_id</c> keep the names the GDScript version uses.
/// </remarks>
public partial class StoryScene : Control
{
    /// <summary>Characters of a line typed out per tick.</summary>
    public const int RevealPerTick = 3;
    /// <summary>Ticks between taking a choice and the next line.</summary>
    public const int TurnTicks = 12;
    public const int ChoiceFontSize = 22;
    private static readonly string[] ChapterKeys = { "", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3" };
    private static readonly Dictionary<string, string> SpeakerKeys = new()
    {
        ["narrator"] = "SPEAKER_NARRATOR",
        ["stranger"] = "SPEAKER_STRANGER",
    };
    private static readonly StringName AcceptAction = "ui_accept";

    private int _wait;
    private int _shown;
    private string _pending = "";

    private Backdrop _backdrop = null!;
    private Control _panel = null!;
    private Label _speaker = null!;
    private Label _text = null!;
    private VBoxContainer _choices = null!;
    private Label _chapterLabel = null!;

    public StoryGraph graph { get; private set; } = null!;
    public Story? story { get; private set; }

    /// <summary>"reading" (the line is being typed), "choosing", "turning" (a choice taken) or "ended".</summary>
    public string state { get; private set; } = "reading";

    /// <summary>The id of the node the story is at.</summary>
    public string node => story?.NodeId ?? "";

    public int chapter => story?.Current()?.Chapter ?? 0;

    public override void _Ready()
    {
        _backdrop = GetNode<Backdrop>("Backdrop");
        _panel = GetNode<Control>("Panel");
        _speaker = GetNode<Label>("Panel/Speaker");
        _text = GetNode<Label>("Panel/Text");
        _choices = GetNode<VBoxContainer>("Choices");
        _chapterLabel = GetNode<Label>("HUD/ChapterLabel");
        graph ??= StoryGraph.FromFiles();
        _panel.GuiInput += OnPanelInput;
        start_new();
    }

    /// <summary>A new story from the first node.</summary>
    public void start_new()
    {
        story = new Story(graph);
        story.NodeEntered += OnNodeEntered;
        GD.Print($"[Story] begin at {story.NodeId}");
        ShowNode();
    }

    private void ShowNode()
    {
        GD.Print($"[Story] node {story!.NodeId}");
        ClearChoices();
        _shown = 0;
        state = "reading";
        StoryNode? current = story.Current();
        _speaker.Text = Tr(SpeakerKeys.TryGetValue(current?.Speaker ?? "", out string? key) ? key : "SPEAKER_NARRATOR");
        _text.Text = Tr(current?.Text ?? "");
        _text.VisibleCharacters = 0;
        _chapterLabel.Text = Tr(ChapterKeys[Math.Clamp(chapter, 0, ChapterKeys.Length - 1)]);
        _backdrop.Chapter = chapter;
    }

    /// <summary>The whole line at once (a click on the text, or ui_accept).</summary>
    public void reveal_all()
    {
        if (state == "reading")
            _shown = _text.Text.Length;
    }

    private void OnPanelInput(InputEvent @event)
    {
        if (@event is InputEventMouseButton mouse && mouse.Pressed && mouse.ButtonIndex == MouseButton.Left)
            reveal_all();
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed(AcceptAction) && state == "reading")
        {
            reveal_all();
            GetViewport().SetInputAsHandled();
        }
    }

    /// <summary>Takes a choice the story offers now; false when it is not offered or the choices are not shown yet.</summary>
    public bool choose_id(string choiceId)
    {
        if (state != "choosing" || !story!.CanChoose(choiceId))
            return false;
        GD.Print($"[Story] choice {choiceId}");
        foreach (Node child in _choices.GetChildren())
            ((Button)child).Disabled = true;
        _pending = choiceId;
        _wait = TurnTicks;
        state = "turning";
        return true;
    }

    public override void _PhysicsProcess(double delta)
    {
        switch (state)
        {
            case "reading":
                int total = _text.Text.Length;
                if (_shown < total)
                {
                    _shown = Math.Min(_shown + RevealPerTick, total);
                    _text.VisibleCharacters = _shown;
                }
                else
                {
                    _text.VisibleCharacters = -1;
                    OnRevealed();
                }
                break;
            case "turning":
                _wait -= 1;
                if (_wait <= 0)
                    story!.Choose(_pending);
                break;
        }
    }

    private void OnRevealed()
    {
        if (story!.IsOver())
        {
            GD.Print($"[Story] ending {story.Ending()}");
            _speaker.Text = Tr(graph.Ending(story.Ending())!.Title);
            AddButton("Again", Tr("ENDING_AGAIN"), start_new);
            state = "ended";
            return;
        }
        foreach (Choice choice in story.Available())
        {
            string id = choice.Id;
            AddButton($"Choice{_choices.GetChildCount()}", Tr(choice.Text), () => choose_id(id));
        }
        state = "choosing";
    }

    private void AddButton(string buttonName, string text, Action action)
    {
        var button = new Button
        {
            Name = buttonName,
            CustomMinimumSize = new Vector2(0, 88),
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
            Text = text,
        };
        button.AddThemeFontSizeOverride("font_size", ChoiceFontSize);
        button.Pressed += action;
        _choices.AddChild(button);
    }

    private void ClearChoices()
    {
        foreach (Node button in _choices.GetChildren())
        {
            _choices.RemoveChild(button);
            button.QueueFree();
        }
    }

    private void OnNodeEntered(string nodeId)
    {
        ShowNode();
    }
}
