namespace Bramblegate;

using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the map select, the game, settings or victory.
/// Screens are children of Main rather than scene changes, so the save and the data live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _mapSelectScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _settings = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = null!;
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Catalog Catalog { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _mapSelectScene = GD.Load<PackedScene>("res://ui/map_select.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        Catalog = Catalog.FromFiles();
        _start.Pressed += ShowMapSelect;
        _settings.Pressed += ShowSettings;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        ShowMenu();
        if (Options.Autoplay)
            StartMap(Options.Map);
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
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
    }

    public void ShowMapSelect()
    {
        var select = _mapSelectScene.Instantiate<MapSelect>();
        select.Name = "MapSelect";
        select.Setup(Catalog, Save);
        select.MapChosen += StartMap;
        select.Closed += ShowMenu;
        ShowScreen(select);
    }

    public void StartMap(int index)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Catalog, Options, index);
        game.MapOver += OnMapOver;
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

    public void ShowMenu()
    {
        CloseScreen();
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

    private void OnMapOver(int level, bool won, int lives, int startLives)
    {
        if (won)
        {
            Progress.Record(Save, Catalog.MapAt(level)!.Id, lives, startLives);
            Store.Write(Save);
        }
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
        if (!victory)
        {
            Callable.From(ShowMenu).CallDeferred();
            return;
        }
        var screen = _victoryScene.Instantiate<Victory>();
        screen.Name = "Victory";
        screen.Setup(Progress.TotalStars(Save));
        screen.MenuPressed += ShowMenu;
        // The game is still inside its own physics step or a button's signal; swap it out once that is over.
        Callable.From(() => ShowScreen(screen)).CallDeferred();
    }

    /// <summary>Lets the freed game's sounds stop before the engine exits, so the exit is clean.</summary>
    private async void QuitAfterFrames(int frames)
    {
        for (int i = 0; i < frames; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        GetTree().Quit();
    }
}
