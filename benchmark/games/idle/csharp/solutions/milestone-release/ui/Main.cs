namespace Duskhive;

using System;
using Godot;

/// <summary>
/// The holder of the hive and of the screen over it (settings, credits), and the keeper of the save. It reads the save
/// at start and pays the time away, and writes it every autosave interval, after a dawn, and when the game is closed,
/// sent to the background or loses focus: a phone may never come back to say goodbye.
/// </summary>
/// <remarks>
/// <c>save_path</c>, <c>clock</c>, <c>game</c>, <c>seen_at</c> and <c>save_now</c> keep the names the GDScript version
/// uses, which tests set before Main enters the tree.
/// </remarks>
public partial class Main : Control
{
    private PackedScene _gameScene = null!;
    private PackedScene _settingsScene = null!;
    private PackedScene _creditsScene = null!;
    private Node? _screen;
    private double _sinceSave;

    /// <summary>Where the save goes; tests point it elsewhere before Main enters the tree.</summary>
    public string save_path = SaveStore.DefaultPath;

    /// <summary>Unix seconds now. Tests replace it, as a player replaces the phone's clock.</summary>
    public Func<double> clock = () => Time.GetUnixTimeFromSystem();

    public LaunchOptions Options { get; private set; } = new();

    public SaveStore Store { get; private set; } = null!;

    public SaveData Save { get; private set; } = new();

    public Catalog Catalog { get; private set; } = null!;

    public Game game { get; private set; } = null!;

    /// <summary>The latest time the game has seen: what the next save keeps for the next offline payment.</summary>
    public double seen_at { get; private set; }

    public override void _Ready()
    {
        _gameScene = GD.Load<PackedScene>("res://game/game.tscn");
        _settingsScene = GD.Load<PackedScene>("res://ui/settings.tscn");
        _creditsScene = GD.Load<PackedScene>("res://ui/credits.tscn");
        Options = LaunchOptions.FromCommandLine();
        Store = new SaveStore(ProjectSettings.GlobalizePath(save_path)) { Enabled = !Options.NoSave };
        Save = Store.Read();
        ApplySettings(Save);
        Catalog = Catalog.FromFiles();
        game = _gameScene.Instantiate<Game>();
        game.Name = "Game";
        game.Setup(Catalog, Options, Save.Economy);
        game.SettingsRequested += ShowSettings;
        game.Dawned += OnDawned;
        game.Finished += OnFinished;
        AddChild(game);
        PayTimeAway();
    }

    /// <summary>Pays the economy for the time since the save, as Offline allows, and shows what it earned.</summary>
    private void PayTimeAway()
    {
        double now = clock();
        if (Save.SavedAt <= 0.0)
        {
            seen_at = now;
            return;
        }
        seen_at = Offline.SeenAt(Save.SavedAt, now);
        if (Options.Autoplay)
            return;
        TimeAway away = Offline.Apply(game.economy, Save.SavedAt, now);
        game.show_welcome(away.Seconds, away.Glow);
    }

    public static void ApplySettings(SaveData save)
    {
        TranslationServer.SetLocale(save.Locale);
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max((float)save.Volume, 0.0001f)));
    }

    /// <summary>Writes the save now: the economy, the latest time seen and the settings.</summary>
    public bool save_now()
    {
        seen_at = Offline.SeenAt(seen_at, clock());
        Save.Economy = game.economy.ToDict();
        Save.SavedAt = seen_at;
        return Store.Write(Save);
    }

    public override void _Process(double delta)
    {
        _sinceSave += delta;
        if (_sinceSave >= Catalog.Setting("autosave_seconds"))
        {
            _sinceSave = 0.0;
            save_now();
        }
    }

    public override void _Notification(int what)
    {
        if (!IsNodeReady())
            return;
        if (what == NotificationWMCloseRequest || what == NotificationApplicationPaused || what == NotificationApplicationFocusOut)
            save_now();
    }

    public void ShowSettings()
    {
        var settings = _settingsScene.Instantiate<Settings>();
        settings.Name = "Settings";
        settings.Setup(Save);
        settings.Closed += OnSettingsClosed;
        settings.CreditsRequested += ShowCredits;
        ShowScreen(settings);
    }

    public void ShowCredits()
    {
        var credits = _creditsScene.Instantiate<Credits>();
        credits.Name = "Credits";
        credits.Closed += ShowSettings;
        ShowScreen(credits);
    }

    /// <summary>Closes whatever screen is over the hive.</summary>
    public void CloseScreen()
    {
        if (_screen != null)
        {
            RemoveChild(_screen);
            _screen.QueueFree();
            _screen = null;
        }
        game.Visible = true;
    }

    private void ShowScreen(Node screen)
    {
        CloseScreen();
        game.Visible = false;
        _screen = screen;
        AddChild(screen);
    }

    private void OnSettingsClosed()
    {
        save_now();
        CloseScreen();
    }

    private void OnDawned(double embers)
    {
        save_now();
    }

    private void OnFinished()
    {
        if (Options.Autoplay)
        {
            // A bot run ends here; free the game first so nothing is left in use when the engine exits.
            Callable.From(EndRun).CallDeferred();
        }
    }

    private async void EndRun()
    {
        CloseScreen();
        // Stop the game and let its sounds end before freeing it, or their playbacks outlive the engine.
        game.ProcessMode = ProcessModeEnum.Disabled;
        game.StopSounds();
        for (int i = 0; i < 10; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        RemoveChild(game);
        game.QueueFree();
        for (int i = 0; i < 3; i++)
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        GetTree().Quit();
    }
}
