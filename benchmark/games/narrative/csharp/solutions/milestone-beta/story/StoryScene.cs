namespace SaltmereCrossing;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// The story on screen: the line of the node the story is at, typed out, then the choices it offers; history, pause and
/// the ending panel. Main starts it with Setup(); on its own (a flow, a test, the editor) it reads the command line and
/// the data itself.
/// The story itself lives in Story; this node only paces it. A line appears a few characters a tick, a choice taken
/// turns the page for a moment before the story moves on, and the bot thinks before each choice. Everything runs in
/// _PhysicsProcess at 60 ticks, so a bot run replays the same on every machine.
/// </summary>
/// <remarks>
/// <c>story</c>, <c>graph</c>, <c>found</c>, <c>node</c>, <c>chapter</c>, <c>state</c>, <c>choice_checks</c> and the
/// methods <c>start_new</c>, <c>resume</c>, <c>reveal_all</c>, <c>choose</c>, <c>choose_id</c>, <c>history_lines</c> and
/// <c>open_history</c> keep the names the UI flows and the GDScript version use: the flows are shared, word for word.
/// </remarks>
public partial class StoryScene : Control
{
    /// <summary>Characters of a line typed out per tick.</summary>
    public const int RevealPerTick = 3;
    /// <summary>
    /// Ticks between taking a choice and the next line: longer than the juice window, so a choice's sound never stands in
    /// for the feedback of what the choice causes.
    /// </summary>
    public const int TurnTicks = 12;
    /// <summary>Ticks the bot reads the choices before it takes one.</summary>
    public const int ThinkTicks = 20;
    /// <summary>Ticks an ending's line stays before the ending panel opens.</summary>
    public const int EndingPanelTicks = 30;
    /// <summary>How long a bot run shows the ending panel before the next story.</summary>
    public const int AutoplayNextTicks = 40;
    public const int ChoiceFontSize = 22;
    private static readonly string[] ChapterKeys = { "", "CHAPTER_1", "CHAPTER_2", "CHAPTER_3" };
    private static readonly Dictionary<string, string> SpeakerKeys = new()
    {
        ["narrator"] = "SPEAKER_NARRATOR",
        ["stranger"] = "SPEAKER_STRANGER",
    };
    private static readonly StringName AcceptAction = "ui_accept";
    private static readonly StringName ChoiceMeta = "choice";

    /// <summary>A node was shown: Main keeps the story in the save, so Continue carries on from here.</summary>
    public event Action<JsonObject>? Checkpoint;
    /// <summary>The story reached an ending: Main records it.</summary>
    public event Action<string>? EndingFound;
    /// <summary>A bot run is over: every ending it could reach was reached.</summary>
    public event Action? Finished;
    public event Action? MenuRequested;

    private JsonObject? _saved;
    private int _ticks;
    private int _wait;
    private int _shown;
    private string _pending = "";
    private float _flash;
    /// <summary>The bot's way to its next ending, and the endings it reached or gave up on in this run.</summary>
    private List<string> _plan = new();
    private string _target = "";
    private readonly List<string> _botReached = new();
    private readonly List<string> _botMissed = new();

    private Backdrop _backdrop = null!;
    private ColorRect _flashRect = null!;
    private Control _panel = null!;
    private Label _speaker = null!;
    private Label _text = null!;
    private VBoxContainer _choices = null!;
    private Label _chapterLabel = null!;
    private Button _historyButton = null!;
    private Button _pauseButton = null!;
    private History _history = null!;
    private PauseMenu _pauseMenu = null!;
    private EndingMenu _endingMenu = null!;
    private AudioStreamPlayer _sfxChoice = null!;
    private AudioStreamPlayer _sfxTrust = null!;
    private AudioStreamPlayer _sfxEnding = null!;

    public StoryGraph graph { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;
    public Story? story { get; private set; }

    /// <summary>The ids of the endings found so far (the save's list, shared with Main).</summary>
    public List<string> found { get; private set; } = new();

    /// <summary>
    /// "reading" (the line is being typed), "choosing", "turning" (a choice taken), "ending" (an ending's line shown),
    /// "ended" (the ending panel is open) or "done" (a bot run is over).
    /// </summary>
    public string state { get; private set; } = "reading";

    /// <summary>How many times the choices were worked out, for the performance test.</summary>
    public int choice_checks { get; private set; }

    /// <summary>The id of the node the story is at.</summary>
    public string node => story?.NodeId ?? "";

    public int chapter => story?.Current()?.Chapter ?? 0;

    /// <summary>found: the save's list of endings found; saved: a story from the save to carry on instead of a new one.</summary>
    public void Setup(StoryGraph storyGraph, LaunchOptions options, List<string> foundEndings, JsonObject? saved = null)
    {
        graph = storyGraph;
        Options = options;
        found = foundEndings;
        _saved = saved;
    }

    public override void _Ready()
    {
        _backdrop = GetNode<Backdrop>("Backdrop");
        _flashRect = GetNode<ColorRect>("Flash");
        _panel = GetNode<Control>("Panel");
        _speaker = GetNode<Label>("Panel/Speaker");
        _text = GetNode<Label>("Panel/Text");
        _choices = GetNode<VBoxContainer>("Choices");
        _chapterLabel = GetNode<Label>("HUD/ChapterLabel");
        _historyButton = GetNode<Button>("HUD/HistoryButton");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _history = GetNode<History>("History");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _endingMenu = GetNode<EndingMenu>("EndingMenu");
        _sfxChoice = GetNode<AudioStreamPlayer>("SfxChoice");
        _sfxTrust = GetNode<AudioStreamPlayer>("SfxTrust");
        _sfxEnding = GetNode<AudioStreamPlayer>("SfxEnding");

        Options ??= LaunchOptions.FromCommandLine();
        graph ??= StoryGraph.FromFiles();
        _historyButton.Pressed += open_history;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => MenuRequested?.Invoke();
        _endingMenu.AgainPressed += start_new;
        _endingMenu.MenuPressed += () => MenuRequested?.Invoke();
        _panel.GuiInput += OnPanelInput;
        if (_saved == null)
            start_new();
        else
            resume(_saved);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    /// <summary>A new story from the first node.</summary>
    public void start_new()
    {
        Begin(new Story(graph));
    }

    /// <summary>Carries on a story kept in the save (Story.ToDict()).</summary>
    public void resume(JsonObject data)
    {
        Begin(Story.FromDict(graph, data));
    }

    private void Begin(Story next)
    {
        story = next;
        story.NodeEntered += OnNodeEntered;
        story.FlagChanged += OnFlagChanged;
        story.Ended += OnEnded;
        _endingMenu.Close();
        _history.Close();
        GD.Print($"[Story] begin at {story.NodeId}");
        if (Options.Autoplay)
            PlanNext();
        ShowNode();
    }

    /// <summary>Shows the node the story is at: its speaker and chapter at once, its line typed out from the start.</summary>
    private void ShowNode()
    {
        GD.Print($"[Story] node {story!.NodeId}");
        ClearChoices();
        _shown = 0;
        state = "reading";
        RefreshText();
        if (!story.IsOver())
            Checkpoint?.Invoke(story.ToDict());
    }

    private void RefreshText()
    {
        _historyButton.Text = Tr("HUD_HISTORY");
        _pauseButton.Text = Tr("HUD_PAUSE");
        if (story == null)
            return;
        StoryNode? current = story.Current();
        _speaker.Text = Tr(SpeakerKeys.TryGetValue(current?.Speaker ?? "", out string? key) ? key : "SPEAKER_NARRATOR");
        _text.Text = Tr(current?.Text ?? "");
        _text.VisibleCharacters = state != "reading" ? -1 : _shown;
        _chapterLabel.Text = Tr(ChapterKeys[Math.Clamp(chapter, 0, ChapterKeys.Length - 1)]);
        _backdrop.Chapter = chapter;
        foreach (Node child in _choices.GetChildren())
        {
            var button = (Button)child;
            button.Text = Tr(graph.Choice(button.GetMeta(ChoiceMeta).AsString())?.Text ?? "");
        }
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

    /// <summary>Takes the choice of this index among those shown.</summary>
    public bool choose(int index)
    {
        if (index < 0 || index >= _choices.GetChildCount())
            return false;
        return choose_id(_choices.GetChild(index).GetMeta(ChoiceMeta).AsString());
    }

    /// <summary>Takes a choice the story offers now; false when it is not offered or the choices are not shown yet.</summary>
    public bool choose_id(string choiceId)
    {
        if (state != "choosing" || !story!.CanChoose(choiceId))
            return false;
        GD.Print($"[Story] choice {choiceId}");
        Event("choice_made");
        Play(_sfxChoice);
        foreach (Node child in _choices.GetChildren())
            ((Button)child).Disabled = true;
        _pending = choiceId;
        _wait = TurnTicks;
        state = "turning";
        return true;
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects((float)delta);
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
            case "choosing":
                if (Options.Autoplay)
                {
                    _wait -= 1;
                    if (_wait <= 0)
                        BotChoose();
                }
                break;
            case "ending":
                _wait -= 1;
                if (_wait <= 0)
                {
                    _endingMenu.Open(graph.Ending(story!.Ending())!.Title, found.Count, graph.EndingIds.Count);
                    state = "ended";
                    _wait = AutoplayNextTicks;
                }
                break;
            case "ended":
                if (Options.Autoplay)
                {
                    _wait -= 1;
                    if (_wait <= 0)
                        BotNext();
                }
                break;
        }
    }

    private void OnRevealed()
    {
        if (story!.IsOver())
        {
            state = "ending";
            _wait = EndingPanelTicks;
            return;
        }
        ShowChoices();
        state = "choosing";
        _wait = ThinkTicks;
    }

    /// <summary>One button per choice the story offers, Choice0 first, worked out once per line.</summary>
    private void ShowChoices()
    {
        choice_checks += 1;
        ClearChoices();
        foreach (Choice choice in story!.Available())
        {
            string id = choice.Id;
            var button = new Button
            {
                Name = $"Choice{_choices.GetChildCount()}",
                CustomMinimumSize = new Vector2(0, 88),
                FocusMode = FocusModeEnum.All,
                AutowrapMode = TextServer.AutowrapMode.WordSmart,
                Text = Tr(choice.Text),
            };
            button.AddThemeFontSizeOverride("font_size", ChoiceFontSize);
            button.SetMeta(ChoiceMeta, id);
            button.Pressed += () => choose_id(id);
            _choices.AddChild(button);
        }
        if (_choices.GetChildCount() > 0 && !Options.Autoplay)
            _choices.GetChild(0).CallDeferred(Control.MethodName.GrabFocus);
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

    private void OnFlagChanged(string flag, int before, int after)
    {
        if (flag == "trust" && after > before)
        {
            Event("trust_gained");
            _backdrop.Glow = 1.0f;
            Feedback("glow");
            Play(_sfxTrust);
        }
    }

    private void OnEnded(string endingId)
    {
        GD.Print($"[Story] ending {endingId}");
        if (!found.Contains(endingId))
            found.Add(endingId);
        Event("ending_reached");
        FlashScreen(new Color(1.0f, 0.92f, 0.7f, 0.45f));
        Play(_sfxEnding);
        EndingFound?.Invoke(endingId);
    }

    /// <summary>The lines so far, for the history panel: each node's line and, after it, the choice taken there.</summary>
    public List<string> history_lines()
    {
        var lines = new List<string>();
        string at = graph.Start;
        lines.Add(Tr(graph.Node(at)?.Text ?? ""));
        foreach (string id in story!.History)
        {
            Choice? choice = graph.Choice(id);
            lines.Add(TextFormat.Fill(Tr("HISTORY_CHOICE"), Tr(choice?.Text ?? "")));
            at = choice?.To ?? "";
            lines.Add(Tr(graph.Node(at)?.Text ?? ""));
        }
        return lines;
    }

    public void open_history()
    {
        _history.Open(history_lines());
    }

    // ---- The bot (--autoplay): every ending in turn, by the shortest way StoryCheck finds ----

    private void PlanNext()
    {
        _plan = new List<string>();
        _target = "";
        foreach (string id in graph.EndingIds)
        {
            if (_botReached.Contains(id) || _botMissed.Contains(id))
                continue;
            List<string> path = StoryCheck.PathTo(graph, id, story);
            if (path.Count == 0)
            {
                GD.Print($"[Run] no way to ending {id}");
                _botMissed.Add(id);
                continue;
            }
            _target = id;
            _plan = new List<string>(path);
            return;
        }
    }

    private void BotChoose()
    {
        if (_plan.Count == 0)
            PlanNext();
        if (_plan.Count == 0)
        {
            BotFinish();
            return;
        }
        string id = _plan[0];
        _plan.RemoveAt(0);
        if (!choose_id(id))
        {
            GD.PushError($"The bot's choice {id} is not offered at {story!.NodeId}");
            BotFinish();
        }
    }

    private void BotNext()
    {
        if (!_botReached.Contains(story!.Ending()))
            _botReached.Add(story.Ending());
        if (_botReached.Count + _botMissed.Count < graph.EndingIds.Count)
        {
            start_new();
            if (_target.Length > 0)
                return;
        }
        BotFinish();
    }

    private void BotFinish()
    {
        GD.Print($"[Run] endings found {_botReached.Count} of {graph.EndingIds.Count}");
        if (_botReached.Count == graph.EndingIds.Count)
            GD.Print("[Run] every ending");
        state = "done";
        Finished?.Invoke();
        // On its own (a flow, or the story scene run alone) nobody listens; a bot run then ends here.
        if (Finished == null)
            GetTree().Quit();
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together.
    private void Event(string name)
    {
        GD.Print($"[juice] event {name} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void Feedback(string kind)
    {
        GD.Print($"[juice] feedback {kind} {GameMs().ToString("0.0", CultureInfo.InvariantCulture)}");
    }

    private void FlashScreen(Color color)
    {
        _flash = color.A;
        _flashRect.Color = color;
        Feedback("flash");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        Feedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        _flash = Mathf.Max(_flash - delta * 1.5f, 0f);
        Color color = _flashRect.Color;
        color.A = _flash;
        _flashRect.Color = color;
        _backdrop.Glow = Mathf.Max(_backdrop.Glow - delta * 1.2f, 0f);
    }
}
