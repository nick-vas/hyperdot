namespace Wickerdeep;

using System;
using Godot;

/// <summary>
/// A run down the crypt, one floor at a time: the floor drawn and the HUD. The rules live in World; this node feeds it
/// the player's input (or the bot's) once per physics tick, at 60 ticks, so a bot run replays the same on every machine,
/// and shows what happened. A run that ends, either way, is followed by a new one.
/// </summary>
/// <remarks>
/// <c>run</c>, <c>world</c>, <c>state</c>, <c>floor_number</c>, <c>hp</c>, <c>enemies_left</c>, <c>wick_cell</c> and the
/// methods <c>start_run</c> and <c>start_floor</c> keep the names the GDScript version uses.
/// </remarks>
public partial class Game : Node2D
{
    /// <summary>Pixels a cell is drawn at.</summary>
    public const int TileSize = 22;
    /// <summary>Where the HUD ends: the floor is drawn below it, centred.</summary>
    public const float Top = 112f;
    /// <summary>Ticks the stairs take before the next floor.</summary>
    public const int NextFloorTicks = 30;
    /// <summary>Ticks a finished run stays on screen before the next one.</summary>
    public const int NextRunTicks = 60;
    public const int WickHp = 5;

    private static readonly StringName MoveUp = "move_up";
    private static readonly StringName MoveDown = "move_down";
    private static readonly StringName MoveLeft = "move_left";
    private static readonly StringName MoveRight = "move_right";
    private static readonly StringName AttackAction = "attack";

    private Bot? _bot;
    private int _runs;
    private int _wait;

    private Tiles _tiles = null!;
    private Creatures _creatures = null!;
    private Label _floorLabel = null!;
    private Label _hpLabel = null!;
    private Label _embersLabel = null!;
    private Label _enemiesLabel = null!;

    public Floors Floors { get; private set; } = null!;
    public LaunchOptions Options { get; private set; } = null!;

    public Run? run { get; private set; }

    public World? world { get; private set; }

    /// <summary>"playing", "between" (floors) or "over".</summary>
    public string state { get; private set; } = "playing";

    public int floor_number => run?.FloorNumber ?? 0;

    public int hp => world?.Wick.Hp ?? 0;

    public int enemies_left => world?.Enemies.Count ?? 0;

    public Vector2I wick_cell => world?.Wick.Cell ?? Vector2I.Zero;

    public override void _Ready()
    {
        _tiles = GetNode<Tiles>("Tiles");
        _creatures = GetNode<Creatures>("Creatures");
        _floorLabel = GetNode<Label>("HUD/FloorLabel");
        _hpLabel = GetNode<Label>("HUD/HpLabel");
        _embersLabel = GetNode<Label>("HUD/EmbersLabel");
        _enemiesLabel = GetNode<Label>("HUD/EnemiesLabel");
        Options = LaunchOptions.FromCommandLine();
        Floors = Floors.FromFiles();
        if (Options.Autoplay)
            _bot = new Bot();
        start_run();
    }

    /// <summary>A new run from the first floor (or --floor), with the session's next seed.</summary>
    /// <remarks>An overload, not a default argument: the engine (a flow's call step) calls a C# method only with all its arguments.</remarks>
    public void start_run() => start_run(-1);

    /// <summary>A new run from the first floor (or --floor); seed -1 takes the session's next seed.</summary>
    public void start_run(long seed)
    {
        run = new Run(seed >= 0 ? seed : NextSeed(), WickHp);
        start_floor(Floors.HasFloor(Options.FloorNumber) ? Options.FloorNumber : 1);
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
        world.EnemySnuffed += _ => Refresh();
        world.WickHurt += _ => Refresh();
        world.StairsOpened += OnStairsOpened;
        GD.Print($"[Run] floor {number}, seed {run.FloorSeed()}: {dungeon.Rooms.Count} rooms, {world.Enemies.Count} enemies");
        state = "playing";
        var origin = new Vector2((GetViewportRect().Size.X - dungeon.Width * TileSize) / 2f, Top);
        _tiles.Position = origin;
        _creatures.Position = origin;
        _tiles.ShowDungeon(dungeon, world);
        _creatures.ShowWorld(world);
        Refresh();
    }

    public override void _PhysicsProcess(double delta)
    {
        _creatures.Advance((float)delta);
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
        {
            GD.Print($"[Run] died on floor {run!.FloorNumber}");
            state = "over";
            _wait = NextRunTicks;
        }
        else if (world.Done)
        {
            FloorCleared();
        }
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
        }
        else
        {
            GD.Print("[Run] victory");
            state = "over";
            if (Options.Autoplay)
            {
                GetTree().Quit();
                return;
            }
        }
        _wait = state == "between" ? NextFloorTicks : NextRunTicks;
        Refresh();
    }

    private void AfterWait()
    {
        if (state == "between")
            start_floor(run!.FloorNumber + 1);
        else
            start_run();
    }

    private void Refresh()
    {
        if (world == null || run == null || !IsNodeReady())
            return;
        _floorLabel.Text = $"Floor {run.FloorNumber}";
        _hpLabel.Text = $"Wick: {world.Wick.Hp} / {world.Wick.MaxHp}";
        _embersLabel.Text = $"Embers: {run.Embers + world.Embers}";
        _enemiesLabel.Text = world.StairsOpen ? "The stairs are open" : $"Enemies left: {world.Enemies.Count}";
    }

    private void OnStairsOpened()
    {
        _tiles.QueueRedraw();
        Refresh();
    }
}
