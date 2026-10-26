namespace Glimmerpit;

using System.Collections.Generic;
using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the game, the join screen or settings.
/// Screens are children of Main rather than scene changes, so the settings and the network session live in one place.
/// Started as a dedicated server or a soak process (--server, --soak-role), it shows nothing and runs Headless instead.
/// </summary>
public partial class Main : Control
{
    /// <summary>Physics frames a bot run shows the finished match.</summary>
    public const int AutoplayQuitFrames = 60;

    private PackedScene _gameScene = null!;
    private PackedScene _joinScene = null!;
    private PackedScene _settingsScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _play = null!;
    private Button _host = null!;
    private Button _join = null!;
    private Button _settings = null!;
    private Button _quit = null!;
    private Label _status = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SettingsStore? Store { get; private set; }
    public SettingsData Saved { get; private set; } = new();
    public NetSession? Session { get; private set; }
    public List<Court> Courts { get; private set; } = new();

    public override void _Ready()
    {
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _play = GetNode<Button>("Menu/PlayButton");
        _host = GetNode<Button>("Menu/HostButton");
        _join = GetNode<Button>("Menu/JoinButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _status = GetNode<Label>("StatusLabel");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        if (Options.Server || Options.SoakRole != "")
        {
            _menu.Visible = false;
            var headless = new Headless { Name = "Headless" };
            headless.Setup(Options);
            AddChild(headless);
            return;
        }
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _joinScene = GD.Load<PackedScene>("res://ui/join.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        Store = new SettingsStore(ProjectSettings.GlobalizePath("user://settings.json")) { Enabled = !Options.NoSave };
        Saved = Store.Read();
        ApplySettings(Saved);
        // The courts are read once, here: every match and every rematch plays them.
        Courts = Court.LoadAll();
        _play.Pressed += () => StartGame("local");
        _host.Pressed += () => StartGame("host");
        _join.Pressed += ShowJoin;
        _settings.Pressed += ShowSettings;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        ShowMenu();
        if (Options.Autoplay)
            StartGame("local");
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady() && Store != null)
            RefreshText();
    }

    private void RefreshText()
    {
        _title.Text = Tr("MENU_TITLE");
        _play.Text = Tr("MENU_PLAY");
        _host.Text = Tr("MENU_HOST");
        _join.Text = Tr("MENU_JOIN");
        _settings.Text = Tr("MENU_SETTINGS");
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SettingsData values)
    {
        TranslationServer.SetLocale(values.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)values.Volume, 0.0001f)));
    }

    /// <summary>Starts a match: "local" against bots, "host" for others to join on the port, "join" to a server at an address.</summary>
    public void StartGame(string mode, string address = "")
    {
        _status.Text = "";
        if (mode != "local")
        {
            OpenSession();
            Error err = mode == "host" ? Session!.Host(Options.Port) : Session!.Join(address, Options.Port);
            if (err != Error.Ok)
            {
                CloseSession();
                ShowMenu();
                _status.Text = TextFormat.Fill(Tr("MENU_NET_FAILED"), err.ToString());
                return;
            }
            Session.Disconnected += OnDisconnected;
        }
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(mode, Options, Session, Courts);
        game.MatchOver += OnMatchOver;
        game.MenuRequested += ShowMenu;
        ShowScreen(game);
    }

    public void ShowJoin()
    {
        var join = _joinScene.Instantiate<Join>();
        join.Name = "Join";
        join.JoinPressed += address => StartGame("join", address);
        join.Closed += ShowMenu;
        ShowScreen(join);
    }

    public void ShowSettings()
    {
        var screen = _settingsScene.Instantiate<Settings>();
        screen.Name = "Settings";
        screen.Setup(Saved);
        screen.Closed += OnSettingsClosed;
        ShowScreen(screen);
    }

    public void ShowMenu()
    {
        CloseScreen();
        CloseSession();
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

    private void OpenSession()
    {
        CloseSession();
        Session = new NetSession { Name = "Net" };
        AddChild(Session);
    }

    private void CloseSession()
    {
        if (Session == null)
            return;
        Session.Close();
        RemoveChild(Session);
        Session.QueueFree();
        Session = null;
    }

    private void OnDisconnected(string reason)
    {
        Callable.From(ShowMenu).CallDeferred();
        _status.Text = Tr("MENU_NET_LOST");
    }

    private void OnSettingsClosed()
    {
        Store!.Write(Saved);
        ShowMenu();
    }

    private void OnMatchOver(bool won)
    {
        Saved.Played++;
        if (won)
            Saved.Won++;
        Store!.Write(Saved);
        if (Options.Autoplay)
            EndBotRun();
    }

    /// <summary>A bot run shows the result for a moment, then frees the game and lets its sounds stop before the engine exits.</summary>
    private async void EndBotRun()
    {
        for (int i = 0; i < AutoplayQuitFrames; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
        CloseScreen();
        for (int i = 0; i < 3; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        GetTree().Quit();
    }
}
