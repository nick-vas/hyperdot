namespace Cinderloop;

using System;
using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the track select, the race, settings, credits or
/// victory. Screens are children of Main rather than scene changes, so the save and the loaded data live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _trackSelectScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _creditsScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _settings = null!;
    private Button _credits = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Tracks Tracks { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _trackSelectScene = GD.Load<PackedScene>("res://ui/track_select.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _creditsScene = GD.Load<PackedScene>("res://ui/credits.tscn");
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _credits = GetNode<Button>("Menu/CreditsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Enabled ? Store.Read() : new SaveData();
        ApplySettings(Save);
        Tracks = Tracks.FromFiles();
        _start.Pressed += ShowTrackSelect;
        _settings.Pressed += ShowSettings;
        _credits.Pressed += ShowCredits;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        if (Options.Autoplay)
            StartRace(Options.Track);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("MENU_TITLE");
        _start.Text = Tr("MENU_START");
        _settings.Text = Tr("MENU_SETTINGS");
        _credits.Text = Tr("MENU_CREDITS");
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    /// <summary>The save's language, volume and rebound keys, applied to the running game.</summary>
    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
        Controls.Apply(save.Controls);
    }

    public void ShowTrackSelect()
    {
        var select = _trackSelectScene.Instantiate<TrackSelect>();
        select.Name = "TrackSelect";
        select.Setup(Tracks, Save.Unlocked, Save.Best);
        select.Chosen += StartRace;
        select.Closed += ShowMenu;
        ShowScreen(select);
    }

    public void StartRace(int id)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        LaunchOptions options = LaunchOptions.FromCommandLine();
        options.Track = Math.Clamp(id, 1, Tracks.Count());
        game.Setup(Tracks, options, Save);
        game.RaceFinished += OnRaceFinished;
        game.Finished += OnFinished;
        game.MenuRequested += ShowMenu;
        ShowScreen(game);
    }

    public void ShowSettings()
    {
        var settings = _settingsScene.Instantiate<Settings>();
        settings.Name = "Settings";
        settings.Setup(Save);
        settings.Closed += OnSettingsClosed;
        ShowScreen(settings);
    }

    public void ShowCredits()
    {
        var credits = _creditsScene.Instantiate<Credits>();
        credits.Name = "Credits";
        credits.Closed += ShowMenu;
        ShowScreen(credits);
    }

    public void ShowMenu()
    {
        CloseScreen();
        RefreshText();
        _menu.Visible = true;
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

    private void OnRaceFinished(int trackId, int place, int bestMs, Ghost? ghost)
    {
        SaveStore.RecordLap(Save, trackId, bestMs, ghost);
        if (place <= Game.TopPlaces)
            Save.Unlocked = Math.Max(Save.Unlocked, Math.Min(trackId + 1, Tracks.Count()));
        Store.Write(Save);
    }

    private void OnFinished(bool victory)
    {
        if (Options.Autoplay)
        {
            // A bot run ends here; free the game first so nothing is left in use when the engine exits.
            Callable.From(CloseScreen).CallDeferred();
            QuitAfterFrames(3);
            return;
        }
        if (victory)
        {
            var screen = _victoryScene.Instantiate<Victory>();
            screen.Name = "Victory";
            screen.MenuPressed += ShowMenu;
            // The game is still inside its own physics step; swap it out once that step is over.
            Callable.From(() => ShowScreen(screen)).CallDeferred();
        }
    }

    /// <summary>Lets the freed game's sounds stop before the engine exits, so the exit is clean.</summary>
    private async void QuitAfterFrames(int frames)
    {
        for (int i = 0; i < frames; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        GetTree().Quit();
    }
}
