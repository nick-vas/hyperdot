namespace Lanternfen;

using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// The title menu, and the holder of whatever screen is showing: the rival select, the game, settings or
/// victory. Screens are children of Main rather than scene changes, so the save and the data live in one place.
/// </summary>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _rivalSelectScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _victoryScene = null!;
    private Node? _screen;
    private Control _menu = null!;
    private Label _title = null!;
    private Button _start = null!;
    private Button _continue = null!;
    private Button _settings = null!;
    private Button _quit = null!;
    private Label _version = null!;

    public LaunchOptions Options { get; private set; } = new();
    public SaveStore Store { get; private set; } = null!;
    public SaveData Save { get; private set; } = new();
    public Rivals Rivals { get; private set; } = null!;
    public Cards Cards { get; private set; } = null!;

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _rivalSelectScene = GD.Load<PackedScene>("res://ui/rival_select.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _victoryScene = GD.Load<PackedScene>("res://ui/victory.tscn");
        _menu = GetNode<Control>("Menu");
        _title = GetNode<Label>("Menu/Title");
        _start = GetNode<Button>("Menu/StartButton");
        _continue = GetNode<Button>("Menu/ContinueButton");
        _settings = GetNode<Button>("Menu/SettingsButton");
        _quit = GetNode<Button>("Menu/QuitButton");
        _version = GetNode<Label>("Menu/VersionLabel");

        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath("user://save.json")) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        Rivals = Rivals.FromFiles();
        Cards = Cards.FromFile();
        _start.Pressed += ShowRivalSelect;
        _continue.Pressed += ContinueDuel;
        _settings.Pressed += ShowSettings;
        _quit.Pressed += () => GetTree().Quit();
        RefreshText();
        ShowMenu();
        if (Options.Autoplay)
            StartRival(Options.Rival);
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
        _continue.Text = Tr("MENU_CONTINUE");
        _settings.Text = Tr("MENU_SETTINGS");
        _quit.Text = Tr("MENU_QUIT");
        _version.Text = TextFormat.Fill(Tr("MENU_VERSION"), ProjectSettings.GetSetting("application/config/version", "").AsString());
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
    }

    public void ShowRivalSelect()
    {
        var select = _rivalSelectScene.Instantiate<RivalSelect>();
        select.Name = "RivalSelect";
        select.Setup(Rivals, Save);
        select.RivalChosen += StartRival;
        select.Closed += ShowMenu;
        ShowScreen(select);
    }

    public void StartRival(int id)
    {
        StartGame(id, null);
    }

    /// <summary>Carries on the duel kept in the save.</summary>
    public void ContinueDuel()
    {
        if (Save.Duel != null)
            StartGame(0, Save.Duel);
    }

    private void StartGame(int id, JsonObject? saved)
    {
        var game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Rivals, Cards, Options, id, saved);
        game.DuelOver += OnDuelOver;
        game.Checkpoint += OnCheckpoint;
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
        _continue.Visible = Save.Duel != null;
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

    /// <summary>The player's turn began: the duel is kept so Continue can carry on from here.</summary>
    private void OnCheckpoint(JsonObject data)
    {
        Save.Duel = data;
        Store.Write(Save);
    }

    private void OnDuelOver(int rival, bool won)
    {
        Ladder.Record(Save, rival, won);
        Save.Duel = null;
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
        if (!victory)
        {
            Callable.From(ShowMenu).CallDeferred();
            return;
        }
        var screen = _victoryScene.Instantiate<Victory>();
        screen.Name = "Victory";
        screen.Setup(Ladder.TotalWins(Save));
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
