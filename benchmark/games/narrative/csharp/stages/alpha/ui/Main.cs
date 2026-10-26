namespace SaltmereCrossing;

using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the story or settings. Screens are children
/// of Main rather than scene changes, so the save and the story data live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _storyScene = null!;
    private PackedScene _settingsScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _new = null!;
    private Button _continue = null!;
    private Button _settings = null!;
    private Button _quit = null!;
    private Label _endings = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public StoryGraph Graph { get; private set; } = null!;

    public override void _Ready()
    {
        _storyScene = GD.Load<PackedScene>("res://story/story.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _new = GetNode<Button>("Menu/NewButton");
        _continue = GetNode<Button>("Menu/ContinueButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _endings = GetNode<Label>("Menu/EndingsLabel");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        Graph = StoryGraph.FromFiles();
        _new.Pressed += NewStory;
        _continue.Pressed += ContinueStory;
        _settings.Pressed += ShowSettings;
        _quit.Pressed += () => GetTree().Quit();
        ShowMenu();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("MENU_TITLE");
        _new.Text = Tr("MENU_NEW");
        _continue.Text = Tr("MENU_CONTINUE");
        _settings.Text = Tr("MENU_SETTINGS");
        _quit.Text = Tr("MENU_QUIT");
        _endings.Text = TextFormat.Fill(Tr("MENU_ENDINGS"), Save.Endings.Count, Graph.EndingIds.Count);
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
    }

    /// <summary>A story from the first line; a story in progress is given up.</summary>
    public void NewStory()
    {
        StartStory(null);
    }

    /// <summary>Carries on the story kept in the save.</summary>
    public void ContinueStory()
    {
        if (Save.Story != null)
            StartStory(Save.Story);
    }

    private void StartStory(JsonObject? saved)
    {
        var screen = _storyScene.Instantiate<StoryScene>();
        screen.Name = "Story";
        screen.Setup(Graph, Options, Save.Endings, saved);
        screen.Checkpoint += OnCheckpoint;
        screen.EndingFound += OnEndingFound;
        screen.MenuRequested += ShowMenu;
        ShowScreen(screen);
    }

    public void ShowSettings()
    {
        var settings = _settingsScene.Instantiate<Settings>();
        settings.Name = "Settings";
        settings.Setup(Save);
        settings.Closed += OnSettingsClosed;
        ShowScreen(settings);
    }

    public void ShowMenu()
    {
        CloseScreen();
        _menu.Visible = true;
        _continue.Visible = Save.Story != null;
        RefreshText();
    }

    private void ShowScreen(Node screen)
    {
        CloseScreen();
        _menu.Visible = false;
        _screen = screen;
        AddChild(screen);
    }

    private void CloseScreen()
    {
        if (_screen == null)
            return;
        RemoveChild(_screen);
        _screen.QueueFree();
        _screen = null;
    }

    private void OnSettingsClosed()
    {
        Store.Write(Save);
        ShowMenu();
    }

    /// <summary>A line was shown: the story is kept so Continue can carry on from here.</summary>
    private void OnCheckpoint(JsonObject data)
    {
        Save.Story = data;
        Store.Write(Save);
    }

    private void OnEndingFound(string endingId)
    {
        SaveStore.RecordEnding(Save, endingId);
        Save.Story = null;
        Store.Write(Save);
    }
}
