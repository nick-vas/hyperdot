namespace Wickerdeep;

using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the game, the shrine, settings or credits. Screens are
/// children of Main rather than scene changes, so the save and the data live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _shrineScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _creditsScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Label _embers = null!;
    private Button _start = null!;
    private Button _continue = null!;
    private Button _shrine = null!;
    private Button _settings = null!;
    private Button _credits = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Floors Floors { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _shrineScene = GD.Load<PackedScene>("res://ui/shrine.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _creditsScene = GD.Load<PackedScene>("res://ui/credits.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _embers = GetNode<Label>("Menu/EmbersLabel");
        _start = GetNode<Button>("Menu/StartButton");
        _continue = GetNode<Button>("Menu/ContinueButton");
        _shrine = GetNode<Button>("Menu/ShrineButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _credits = GetNode<Button>("Menu/CreditsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        Floors = Floors.FromFiles();
        _start.Pressed += StartRun;
        _continue.Pressed += ContinueRun;
        _shrine.Pressed += ShowShrine;
        _settings.Pressed += ShowSettings;
        _credits.Pressed += ShowCredits;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        ShowMenu();
        if (Options.Autoplay)
            StartRun();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("MENU_TITLE");
        _embers.Text = TextFormat.Fill(Tr("MENU_EMBERS"), Save.Meta.Embers, Save.Meta.BestFloor);
        _start.Text = Tr("MENU_START");
        _continue.Text = Tr("MENU_CONTINUE");
        _shrine.Text = Tr("MENU_SHRINE");
        _settings.Text = Tr("MENU_SETTINGS");
        _credits.Text = Tr("MENU_CREDITS");
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
    }

    /// <summary>A new run, with the vigor bought at the shrine.</summary>
    public void StartRun()
    {
        StartGame(null);
    }

    /// <summary>Carries on the run kept in the save.</summary>
    public void ContinueRun()
    {
        if (Save.Run != null)
            StartGame(Save.Run);
    }

    private void StartGame(JsonObject? saved)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Floors, Options, Meta.MaxHp(Save), saved);
        game.RunOver += OnRunOver;
        game.Checkpoint += OnCheckpoint;
        game.Finished += OnFinished;
        game.MenuRequested += ShowMenu;
        ShowScreen(game);
    }

    public void ShowShrine()
    {
        var shrine = _shrineScene.Instantiate<Shrine>();
        shrine.Name = "Shrine";
        shrine.Setup(Save);
        shrine.Closed += OnScreenClosed;
        ShowScreen(shrine);
    }

    public void ShowSettings()
    {
        var settings = _settingsScene.Instantiate<Settings>();
        settings.Name = "Settings";
        settings.Setup(Save);
        settings.Closed += OnScreenClosed;
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
        _menu.Visible = true;
        _continue.Visible = Save.Run != null;
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

    private void OnScreenClosed()
    {
        Store.Write(Save);
        ShowMenu();
    }

    /// <summary>A floor began: the run is kept so Continue can carry on from here.</summary>
    private void OnCheckpoint(JsonObject data)
    {
        Save.Run = data;
        Store.Write(Save);
    }

    private void OnRunOver(bool won, int floorNumber, int embers)
    {
        Meta.Bank(Save, embers, floorNumber, won);
        Save.Run = null;
        Store.Write(Save);
    }

    private void OnFinished()
    {
        if (Options.Autoplay)
        {
            // A bot run ends here; free the game first so nothing is left in use when the engine exits.
            Callable.From(CloseScreen).CallDeferred();
            QuitAfterFrames(3);
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
