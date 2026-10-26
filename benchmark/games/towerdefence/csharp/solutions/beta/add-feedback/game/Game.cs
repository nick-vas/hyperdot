namespace Bramblegate;

using System;
using System.Collections.Generic;
using System.Globalization;
using Godot;

/// <summary>
/// One map's battle on screen: the field, the HUD, building, pause and the result panel. Main starts it with Setup(); on
/// its own (a flow, a test, the editor) it reads the command line and the data itself.
/// The rules live in Battle; this node only feeds it ticks and input and shows what it holds. Everything runs in
/// _PhysicsProcess at 60 ticks, so a bot run replays the same on every machine.
/// </summary>
/// <remarks>
/// <c>battle</c>, <c>level</c>, <c>state</c>, <c>building</c>, <c>selected</c>, <c>speed</c>, <c>gold</c>, <c>lives</c>,
/// <c>wave</c>, <c>phase</c> and the methods <c>start_map</c>, <c>place_at</c>, <c>select_tower</c>,
/// <c>upgrade_selected</c>, <c>sell_selected</c>, <c>next_wave</c>, <c>toggle_speed</c>, <c>next_map</c> and
/// <c>retry</c> keep the names the UI flows and the GDScript version use: the flows are shared, word for word.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>How long a bot run shows a finished map before the next one.</summary>
    public const int AutoplayNextTicks = 40;
    /// <summary>The speeds the speed button steps through.</summary>
    private static readonly int[] Speeds = { 1, 3 };
    private static readonly string[] TowerKinds = { "thorn", "puff", "acorn" };
    private static readonly string[] TowerButtonPaths = { "HUD/Towers/ThornButton", "HUD/Towers/PuffButton", "HUD/Towers/AcornButton" };
    private static readonly StringName NextWaveAction = "next_wave";
    private static readonly StringName ToggleSpeedAction = "toggle_speed";

    /// <summary>A map ended: Main records it (level, won, lives, start lives).</summary>
    public event Action<int, bool, int, int>? MapOver;
    /// <summary>The run is over: victory after the last map.</summary>
    public event Action<bool>? Finished;
    public event Action? MenuRequested;

    private int _firstLevel;
    private readonly Button[] _towerButtons = new Button[TowerKinds.Length];
    private Bot? _bot;
    private int _runs;
    private int _ticks;
    private int _nextIn = -1;
    private float _shake;
    private float _flash;
    private readonly RandomNumberGenerator _rng = new();

    private Camera2D _camera = null!;
    private Sprite2D _store = null!;
    private Label _mapLabel = null!;
    private Label _goldLabel = null!;
    private Label _livesLabel = null!;
    private Label _waveLabel = null!;
    private Label _infoLabel = null!;
    private Button _upgrade = null!;
    private Button _sell = null!;
    private Button _nextWave = null!;
    private Button _speedButton = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private ResultMenu _resultMenu = null!;
    private AudioStreamPlayer _sfxPlace = null!;
    private AudioStreamPlayer _sfxKill = null!;
    private AudioStreamPlayer _sfxLeak = null!;
    private AudioStreamPlayer _sfxWin = null!;

    public Catalog Catalog { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;
    public Field Field { get; private set; } = null!;

    public Battle? battle { get; private set; }

    /// <summary>The map's place in the campaign, from 1.</summary>
    public int level { get; private set; } = 1;

    /// <summary>"playing", "over" (the result is shown) or "done".</summary>
    public string state { get; private set; } = "playing";

    /// <summary>The tower kind a click on an open cell builds.</summary>
    public string building { get; private set; } = "thorn";

    /// <summary>The cell of the tower whose upgrade and sale the HUD offers; (-1, -1) for none.</summary>
    public Vector2I selected { get; private set; } = new(-1, -1);

    /// <summary>Battle ticks per physics tick.</summary>
    public int speed { get; set; } = 1;

    public int gold => battle?.Gold ?? 0;

    public int lives => battle?.Lives ?? 0;

    public int wave => battle?.Wave ?? 0;

    public string phase => battle?.PhaseName ?? "";

    /// <summary>firstLevel: the map to play (the command line's --map when 0).</summary>
    public void Setup(Catalog catalog, LaunchOptions options, int firstLevel = 0)
    {
        Catalog = catalog;
        Options = options;
        _firstLevel = firstLevel;
    }

    public override void _Ready()
    {
        Field = GetNode<Field>("Field");
        _camera = GetNode<Camera2D>("Camera");
        _store = GetNode<Sprite2D>("Store");
        _mapLabel = GetNode<Label>("HUD/MapLabel");
        _goldLabel = GetNode<Label>("HUD/GoldLabel");
        _livesLabel = GetNode<Label>("HUD/LivesLabel");
        _waveLabel = GetNode<Label>("HUD/WaveLabel");
        _infoLabel = GetNode<Label>("HUD/InfoLabel");
        _upgrade = GetNode<Button>("HUD/UpgradeButton");
        _sell = GetNode<Button>("HUD/SellButton");
        _nextWave = GetNode<Button>("HUD/NextWaveButton");
        _speedButton = GetNode<Button>("HUD/SpeedButton");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _resultMenu = GetNode<ResultMenu>("ResultMenu");
        _sfxPlace = GetNode<AudioStreamPlayer>("SfxPlace");
        _sfxKill = GetNode<AudioStreamPlayer>("SfxKill");
        _sfxLeak = GetNode<AudioStreamPlayer>("SfxLeak");
        _sfxWin = GetNode<AudioStreamPlayer>("SfxWin");

        Options ??= LaunchOptions.FromCommandLine();
        Catalog ??= Catalog.FromFiles();
        _rng.Seed = unchecked((ulong)Options.RunSeed);
        speed = Options.Speed;
        if (Options.Autoplay)
            _bot = new Bot();
        for (int i = 0; i < TowerKinds.Length; i++)
        {
            string id = TowerKinds[i];
            _towerButtons[i] = GetNode<Button>(TowerButtonPaths[i]);
            _towerButtons[i].Pressed += () => select_tower(id);
        }
        _upgrade.Pressed += () => upgrade_selected();
        _sell.Pressed += () => sell_selected();
        _nextWave.Pressed += next_wave;
        _speedButton.Pressed += toggle_speed;
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => MenuRequested?.Invoke();
        _resultMenu.NextPressed += next_map;
        _resultMenu.RetryPressed += retry;
        _resultMenu.MenuPressed += () => MenuRequested?.Invoke();
        start_map(_firstLevel > 0 ? _firstLevel : Options.Map);
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            Refresh();
    }

    /// <summary>A new battle on the map at this place in the campaign, as start_map(index, -1).</summary>
    /// <remarks>An overload, not a default argument: the engine (a flow's call step) calls a C# method only with all its arguments.</remarks>
    public void start_map(int index) => start_map(index, -1);

    /// <summary>A new battle on the map at this place in the campaign; seed -1 takes the run's next seed.</summary>
    public void start_map(int index, long seed)
    {
        MapRow? row = Catalog.MapAt(index);
        if (row == null)
        {
            GD.PushError($"There is no map {index}");
            return;
        }
        level = index;
        long battleSeed = seed >= 0 ? seed : NextSeed();
        GD.Print($"[Run] map {index}, seed {battleSeed}");
        battle = Battle.Create(Catalog, row.Id, battleSeed)!;
        battle.TowerPlaced += OnTowerPlaced;
        battle.TowerUpgraded += OnTowerChanged;
        battle.TowerSold += OnTowerSold;
        battle.EnemyKilled += OnEnemyKilled;
        battle.EnemyLeaked += OnEnemyLeaked;
        battle.WaveStarted += OnWaveChanged;
        battle.WaveCleared += OnWaveCleared;
        battle.BattleOver += OnBattleOver;
        state = "playing";
        selected = new Vector2I(-1, -1);
        _nextIn = -1;
        _resultMenu.Close();
        Field.ShowBattle(battle);
        _store.Position = Field.CellCentre(battle.Map.Store);
        Refresh();
    }

    /// <summary>The run's seeds: from --seed, one per battle in order, so a bot run replays; at random without it.</summary>
    private long NextSeed()
    {
        _runs += 1;
        if (Options.RunSeed > 0)
            return Options.RunSeed * 1009 + _runs;
        return GD.Randi() % 1000000;
    }

    public void next_map()
    {
        if (state != "over")
            return;
        if (Catalog.MapAt(level + 1) != null)
        {
            start_map(level + 1);
        }
        else
        {
            GD.Print("[Run] victory");
            Finish(true);
        }
    }

    public void retry()
    {
        if (state == "over")
            start_map(level);
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    private bool CanAct() => state == "playing" && _bot == null && !battle!.IsOver();

    public void select_tower(string id)
    {
        building = id;
        selected = new Vector2I(-1, -1);
        Refresh();
    }

    /// <summary>Builds the chosen kind on a cell, or selects the tower already there. For flows and tests as well as clicks.</summary>
    public bool place_at(int x, int y)
    {
        var cell = new Vector2I(x, y);
        if (!CanAct())
            return false;
        if (battle!.Towers.Has(cell))
        {
            selected = cell;
            Refresh();
            return false;
        }
        return battle.Place(building, cell);
    }

    public bool upgrade_selected() => CanAct() && battle!.Upgrade(selected);

    public int sell_selected()
    {
        if (!CanAct() || !battle!.Towers.Has(selected))
            return 0;
        int back = battle.Sell(selected);
        selected = new Vector2I(-1, -1);
        Refresh();
        return back;
    }

    public void next_wave()
    {
        if (CanAct())
            battle!.StartWave();
    }

    public void toggle_speed()
    {
        speed = Speeds[(Array.IndexOf(Speeds, speed) + 1) % Speeds.Length];
        Refresh();
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsActionPressed(NextWaveAction))
        {
            next_wave();
            GetViewport().SetInputAsHandled();
        }
        else if (@event.IsActionPressed(ToggleSpeedAction))
        {
            toggle_speed();
            GetViewport().SetInputAsHandled();
        }
        else if (@event is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left })
        {
            Vector2I cell = Field.CellAt(Field.GetLocalMousePosition());
            if (battle != null && battle.Map.InBounds(cell))
            {
                place_at(cell.X, cell.Y);
                GetViewport().SetInputAsHandled();
            }
        }
    }

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects((float)delta);
        if (state == "over")
        {
            if (_nextIn > 0)
            {
                _nextIn -= 1;
                if (_nextIn == 0)
                    BotNext();
            }
            return;
        }
        if (state != "playing")
            return;
        for (int i = 0; i < speed; i++)
        {
            _bot?.Act(battle!);
            battle!.Step();
            if (battle.IsOver())
                break;
        }
        _waveLabel.Text = WaveText();
        Field.QueueRedraw();
    }

    private string WaveText()
    {
        if (battle!.Phase == Phase.Build)
            return TextFormat.Fill(Tr("HUD_NEXT_WAVE_IN"), battle.Wave + 1, battle.Waves.Count, (int)Math.Ceiling(battle.BreakLeft / (double)Battle.TicksPerSecond));
        return TextFormat.Fill(Tr("HUD_WAVE"), battle.Wave, battle.Waves.Count);
    }

    private void OnBattleOver(bool won)
    {
        state = "over";
        GD.Print($"[Run] map {level} {(won ? "won" : "lost")}");
        if (won)
            _sfxWin.Play();
        MapOver?.Invoke(level, won, battle!.Lives, battle.StartLives);
        Refresh();
        if (_bot != null)
        {
            _nextIn = AutoplayNextTicks;
        }
        else
        {
            bool last = Catalog.MapAt(level + 1) == null;
            _resultMenu.Open(won, won ? Progress.StarsFor(battle!.Lives, battle.StartLives) : 0, last ? "RESULT_FINISH" : "RESULT_NEXT");
        }
    }

    /// <summary>A bot run goes on: the next map after a win, the same one again after a loss, victory after the last.</summary>
    private void BotNext()
    {
        if (battle!.Phase == Phase.Won)
            next_map();
        else
            start_map(level);
    }

    private void Finish(bool victory)
    {
        state = "done";
        Finished?.Invoke(victory);
        // On its own (a flow, or the game scene run alone) nobody listens; a bot run then ends here.
        if (Options.Autoplay && Finished == null)
            GetTree().Quit();
    }

    private void Refresh()
    {
        if (battle == null || !IsNodeReady())
            return;
        _mapLabel.Text = Tr(Catalog.MapAt(level)?.Name ?? "");
        _goldLabel.Text = TextFormat.Fill(Tr("HUD_SAP"), battle.Gold);
        _livesLabel.Text = TextFormat.Fill(Tr("HUD_SEEDS"), battle.Lives);
        _waveLabel.Text = WaveText();
        for (int i = 0; i < TowerKinds.Length; i++)
        {
            string id = TowerKinds[i];
            _towerButtons[i].Text = TextFormat.Fill(Tr("TOWER_BUTTON"), Tr(Catalog.Towers[id].Name), Catalog.Cost(id));
            _towerButtons[i].ButtonPressed = id == building;
        }
        bool hasSelection = battle.Towers.Has(selected);
        _upgrade.Disabled = !(hasSelection && battle.CanUpgrade(selected));
        _sell.Disabled = !hasSelection;
        _upgrade.Text = Tr("HUD_UPGRADE");
        _sell.Text = Tr("HUD_SELL");
        if (hasSelection)
        {
            Tower tower = battle.Towers[selected];
            int price = Catalog.UpgradeCost(tower.Id, tower.Level + 1);
            if (tower.Level < Catalog.MaxLevel(tower.Id))
                _upgrade.Text = TextFormat.Fill(Tr("HUD_UPGRADE_FOR"), price);
            _sell.Text = TextFormat.Fill(Tr("HUD_SELL_FOR"), battle.Refund(selected));
            _infoLabel.Text = TextFormat.Fill(Tr("HUD_TOWER_INFO"), Tr(Catalog.Towers[tower.Id].Name), tower.Level);
        }
        else
        {
            _infoLabel.Text = Tr("HUD_BUILD_HINT");
        }
        _nextWave.Text = Tr("HUD_NEXT_WAVE");
        _nextWave.Disabled = battle.Phase != Phase.Build;
        _speedButton.Text = TextFormat.Fill(Tr("HUD_SPEED"), speed);
        _pauseButton.Text = Tr("HUD_PAUSE");
        Field.Selected = selected;
        Field.QueueRedraw();
    }

    private void OnTowerPlaced(Vector2I cell)
    {
        Event("tower_placed");
        Field.Pop(Field.CellCentre(cell), new Color(0.75f, 1f, 0.6f));
        Feedback("pop");
        Play(_sfxPlace);
        Refresh();
    }

    private void OnTowerChanged(Vector2I cell)
    {
        Refresh();
    }

    private void OnTowerSold(Vector2I cell, int refund)
    {
        Refresh();
    }

    private void OnEnemyKilled(Enemy enemy)
    {
        Event("enemy_killed");
        Field.Pop(Field.ToScreen(enemy.Pos), new Color(1f, 0.9f, 0.5f));
        Feedback("pop");
        Play(_sfxKill);
        Refresh();
    }

    private void OnEnemyLeaked(Enemy enemy)
    {
        Event("enemy_leaked");
        FlashScreen(new Color(1f, 0.3f, 0.2f, 0.35f));
        ShakeCamera(8f);
        Play(_sfxLeak);
        Refresh();
    }

    private void OnWaveChanged(int number)
    {
        Refresh();
    }

    private void OnWaveCleared(int number, int bonus)
    {
        Refresh();
    }

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

    private void ShakeCamera(float amount)
    {
        _shake = amount;
        Feedback("shake");
    }

    private void Play(AudioStreamPlayer player)
    {
        player.Play();
        Feedback("sfx");
    }

    private void UpdateEffects(float delta)
    {
        _flash = Mathf.Max(_flash - delta * 2f, 0f);
        Color color = _flashRect.Color;
        color.A = _flash;
        _flashRect.Color = color;
        _shake = Mathf.Max(_shake - delta * 40f, 0f);
        _camera.Offset = _shake > 0f ? new Vector2(_rng.RandfRange(-_shake, _shake), _rng.RandfRange(-_shake, _shake)) : Vector2.Zero;
    }
}
