namespace Wickerdeep;

using System;
using System.Globalization;
using System.Text.Json.Nodes;
using Godot;

/// <summary>
/// A run down the crypt, one floor at a time: the floor drawn, the HUD, pause and the panel at the end of a run. Main
/// starts it with Setup(); on its own (a flow, a test, the editor) it reads the command line and the data itself.
/// The rules live in World; this node feeds it the player's input (or the bot's) once per physics tick, at 60 ticks,
/// so a bot run replays the same on every machine, and shows what happened.
/// </summary>
/// <remarks>
/// <c>run</c>, <c>world</c>, <c>state</c>, <c>floor_number</c>, <c>hp</c>, <c>enemies_left</c>, <c>wick_cell</c> and the
/// methods <c>start_run</c>, <c>start_floor</c> and <c>resume</c> keep the names the UI flows and the GDScript version
/// use: the flows are shared, word for word.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Pixels a cell is drawn at.</summary>
    public const int TileSize = 22;
    /// <summary>Where the HUD ends: the floor is drawn below it, centred.</summary>
    public const float Top = 112f;
    /// <summary>Ticks the stairs take before the next floor.</summary>
    public const int NextFloorTicks = 30;
    /// <summary>How long a bot run shows a death before it descends again.</summary>
    public const int AutoplayNextTicks = 60;

    private static readonly StringName MoveUp = "move_up";
    private static readonly StringName MoveDown = "move_down";
    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName AttackAction = "attack";

    /// <summary>The run ended: Main banks its embers (won, the floor reached, the run's embers).</summary>
    public event Action<bool, int, int>? RunOver;
    /// <summary>A floor began: Main keeps the run in the save, for Continue.</summary>
    public event Action<JsonObject>? Checkpoint;
    /// <summary>A bot run is over: victory.</summary>
    public event Action? Finished;
    public event Action? MenuRequested;

    private int _maxHp = Meta.BaseHp;
    private JsonObject? _saved;
    private Bot? _bot;
    private int _runs;
    private int _ticks;
    private int _wait;
    private float _shake;
    private float _flash;
    /// <summary>Cosmetic only (the camera's shake): never the world's.</summary>
    private readonly RandomNumberGenerator _rng = new();

    private Camera2D _camera = null!;
    private Tiles _tiles = null!;
    private Creatures _creatures = null!;
    private Label _floorLabel = null!;
    private Label _hpLabel = null!;
    private Label _embersLabel = null!;
    private Label _enemiesLabel = null!;
    private Button _pauseButton = null!;
    private ColorRect _flashRect = null!;
    private PauseMenu _pauseMenu = null!;
    private RunOverMenu _runOverMenu = null!;
    private AudioStreamPlayer _sfxHit = null!;
    private AudioStreamPlayer _sfxHurt = null!;
    private AudioStreamPlayer _sfxSnuff = null!;
    private AudioStreamPlayer _sfxStairs = null!;

    public Floors Floors { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;

    public Run? run { get; private set; }

    public World? world { get; private set; }

    /// <summary>"playing", "between" (floors), "over" (the panel is shown) or "done".</summary>
    public string state { get; private set; } = "playing";

    public int floor_number => run?.FloorNumber ?? 0;

    public int hp => world?.Wick.Hp ?? 0;

    public int enemies_left => world?.Enemies.Count ?? 0;

    public Vector2I wick_cell => world?.Wick.Cell ?? Vector2I.Zero;

    /// <summary>maxHp: the wick's hp with the vigor bought; saved: a run from the save to carry on instead of a new one.</summary>
    public void Setup(Floors floors, LaunchOptions options, int maxHp = Meta.BaseHp, JsonObject? saved = null)
    {
        Floors = floors;
        Options = options;
        _maxHp = maxHp;
        _saved = saved;
    }

    public override void _Ready()
    {
        _camera = GetNode<Camera2D>("Camera");
        _tiles = GetNode<Tiles>("Tiles");
        _creatures = GetNode<Creatures>("Creatures");
        _floorLabel = GetNode<Label>("HUD/FloorLabel");
        _hpLabel = GetNode<Label>("HUD/HpLabel");
        _embersLabel = GetNode<Label>("HUD/EmbersLabel");
        _enemiesLabel = GetNode<Label>("HUD/EnemiesLabel");
        _pauseButton = GetNode<Button>("HUD/PauseButton");
        _flashRect = GetNode<ColorRect>("HUD/Flash");
        _pauseMenu = GetNode<PauseMenu>("PauseMenu");
        _runOverMenu = GetNode<RunOverMenu>("RunOverMenu");
        _sfxHit = GetNode<AudioStreamPlayer>("SfxHit");
        _sfxHurt = GetNode<AudioStreamPlayer>("SfxHurt");
        _sfxSnuff = GetNode<AudioStreamPlayer>("SfxSnuff");
        _sfxStairs = GetNode<AudioStreamPlayer>("SfxStairs");

        Options ??= LaunchOptions.FromCommandLine();
        Floors ??= Floors.FromFiles();
        _rng.Seed = unchecked((ulong)Options.RunSeed);
        _pauseButton.Pressed += _pauseMenu.Open;
        _pauseMenu.QuitPressed += () => MenuRequested?.Invoke();
        _runOverMenu.AgainPressed += start_run;
        _runOverMenu.MenuPressed += () => MenuRequested?.Invoke();
        RefreshText();
        if (_saved != null)
            resume(_saved);
        else
            start_run();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationTranslationChanged && IsNodeReady())
            RefreshText();
    }

    private void RefreshText()
    {
        _pauseButton.Text = Tr("HUD_PAUSE");
        Refresh();
    }

    /// <summary>A new run from the first floor (or --floor), with the session's next seed.</summary>
    /// <remarks>An overload, not a default argument: the engine (a flow's call step) calls a C# method only with all its arguments.</remarks>
    public void start_run() => start_run(-1);

    /// <summary>A new run from the first floor (or --floor); seed -1 takes the session's next seed.</summary>
    public void start_run(long seed)
    {
        run = new Run(seed >= 0 ? seed : NextSeed(), _maxHp);
        start_floor(Floors.HasFloor(Options.FloorNumber) ? Options.FloorNumber : 1);
    }

    /// <summary>Carries on a run kept in the save (Run.ToDict): its floor again from the start, with the hp and embers it had.</summary>
    public void resume(JsonObject data)
    {
        run = Run.FromDict(data);
        start_floor(Floors.HasFloor(run.FloorNumber) ? run.FloorNumber : 1);
    }

    /// <summary>The run's seeds: from --seed, the seed itself and then one more for each run after; at random without it.</summary>
    private long NextSeed()
    {
        _runs += 1;
        if (Options.RunSeed > 0)
            return Options.RunSeed + _runs - 1;
        return GD.Randi() % 1000000 + 1;
    }

    public void start_floor(int number)
    {
        if (run == null)
            return;
        if (Floors.Spec(number) is not FloorSpec spec)
        {
            GD.PushError($"There is no floor {number}");
            return;
        }
        run.FloorNumber = number;
        Dungeon dungeon = Dungeon.Generate(run.FloorSeed(), spec);
        world = World.Create(dungeon, Floors.Kinds, run.FloorSeed(), run.Hp, run.MaxHp);
        if (Options.Swarm > 0 && Floors.Kind("bat") is EnemyStats bat)
            world.AddSwarm(Options.Swarm, bat);
        world.EnemyHit += OnEnemyHit;
        world.EnemySnuffed += OnEnemySnuffed;
        world.WickHurt += OnWickHurt;
        world.StairsOpened += OnStairsOpened;
        GD.Print($"[Run] floor {number}, seed {run.FloorSeed()}: {dungeon.Rooms.Count} rooms, {world.Enemies.Count} enemies");
        state = "playing";
        _runOverMenu.Close();
        var origin = new Vector2((GetViewportRect().Size.X - dungeon.Width * TileSize) / 2f, Top);
        _tiles.Position = origin;
        _creatures.Position = origin;
        _tiles.ShowDungeon(dungeon, world);
        _creatures.ShowWorld(world);
        if (_bot == null)
            Checkpoint?.Invoke(run.ToDict());
        Refresh();
    }

    /// <summary>Game time in milliseconds: physics ticks, never the wall clock.</summary>
    public double GameMs() => _ticks * 1000.0 / Engine.PhysicsTicksPerSecond;

    public override void _PhysicsProcess(double delta)
    {
        _ticks += 1;
        UpdateEffects((float)delta);
        if (_wait > 0)
        {
            _wait -= 1;
            if (_wait == 0)
                AfterWait();
            return;
        }
        if (state != "playing" || world == null)
            return;
        BotChoice choice = _bot != null ? _bot.Choose(world) : ReadInput();
        world.Step(choice.Move, choice.Attack);
        if (world.Wick.Hp <= 0)
            EndRun(false);
        else if (world.Done)
            FloorCleared();
    }

    /// <summary>The player's input this tick: one direction held (up first) and whether attack is held.</summary>
    private static BotChoice ReadInput()
    {
        Vector2I move = Vector2I.Zero;
        if (Input.IsActionPressed(MoveUp))
            move = Vector2I.Up;
        else if (Input.IsActionPressed(MoveDown))
            move = Vector2I.Down;
        else if (Input.IsActionPressed(MoveLeft))
            move = Vector2I.Left;
        else if (Input.IsActionPressed(MoveRight))
            move = Vector2I.Right;
        return new BotChoice(move, Input.IsActionPressed(AttackAction));
    }

    /// <summary>The wick took the stairs: its embers join the run, the stairs' candle relights one hp, and the next floor follows.</summary>
    private void FloorCleared()
    {
        run!.Embers += world!.Embers;
        run.Hp = Math.Min(world.Wick.Hp + 1, run.MaxHp);
        GD.Print($"[Run] floor {run.FloorNumber} cleared");
        if (Floors.HasFloor(run.FloorNumber + 1))
        {
            state = "between";
            _wait = NextFloorTicks;
        }
        else
        {
            GD.Print("[Run] victory");
            EndRun(true);
        }
    }

    private void EndRun(bool won)
    {
        Run ended = run!;
        if (!won)
        {
            ended.Embers += world!.Embers;
            GD.Print($"[Run] died on floor {ended.FloorNumber}");
        }
        state = "over";
        RunOver?.Invoke(won, ended.FloorNumber, ended.Embers);
        if (_bot != null)
        {
            if (won)
                Finish();
            else
                _wait = AutoplayNextTicks;
        }
        else
        {
            _runOverMenu.Open(won, ended.FloorNumber, won ? ended.Embers : ended.Embers / 2);
        }
        Refresh();
    }

    private void AfterWait()
    {
        if (state == "between")
            start_floor(run!.FloorNumber + 1);
        else if (state == "over" && _bot != null)
            start_run();
    }

    private void Finish()
    {
        state = "done";
        Finished?.Invoke();
    }

    private void Refresh()
    {
        if (world == null || run == null || !IsNodeReady())
            return;
        _floorLabel.Text = TextFormat.Fill(Tr("HUD_FLOOR"), run.FloorNumber, Tr(Floors.Spec(run.FloorNumber)?.Name ?? ""));
        _hpLabel.Text = TextFormat.Fill(Tr("HUD_HP"), world.Wick.Hp, world.Wick.MaxHp);
        _embersLabel.Text = TextFormat.Fill(Tr("HUD_EMBERS"), run.Embers + world.Embers);
        _enemiesLabel.Text = world.StairsOpen ? Tr("HUD_STAIRS_OPEN") : TextFormat.Fill(Tr("HUD_ENEMIES"), world.Enemies.Count);
    }

    private void OnEnemyHit(Actor enemy)
    {
        Event("enemy_hit");
        Play(_sfxHit);
    }

    private void OnEnemySnuffed(Actor enemy)
    {
        Event("enemy_snuffed");
        _creatures.Pop(enemy.Cell);
        Feedback("pop");
        Play(_sfxSnuff);
        Refresh();
    }

    private void OnWickHurt(int amount)
    {
        Event("wick_hurt");
        FlashScreen(new Color(1f, 0.25f, 0.15f, 0.4f));
        ShakeCamera(7f);
        Play(_sfxHurt);
        Refresh();
    }

    private void OnStairsOpened()
    {
        _sfxStairs.Play();
        _tiles.QueueRedraw();
        Refresh();
    }

    // Juice: every event and its feedback is logged in game time, so the juice runner can check they come together. The
    // stairs' sound is not logged as feedback, so it cannot stand in for another event's.
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
        _creatures.Advance(delta);
    }
}
