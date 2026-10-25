namespace Bramblegate;

using System;
using Godot;

/// <summary>
/// One map's battle on screen: the field, the HUD and building. The main scene of the prototype.
/// The rules live in Battle; this node only feeds it ticks and input and shows what it holds. Everything runs in
/// _PhysicsProcess at 60 ticks.
/// </summary>
/// <remarks>
/// <c>battle</c>, <c>level</c>, <c>state</c>, <c>building</c>, <c>selected</c>, <c>speed</c>, <c>gold</c>, <c>lives</c>,
/// <c>wave</c>, <c>phase</c> and the methods <c>start_map</c>, <c>place_at</c>, <c>select_tower</c>,
/// <c>upgrade_selected</c>, <c>next_wave</c> and <c>toggle_speed</c> keep the names the GDScript version uses.
/// </remarks>
public partial class Game : Node2D
{
    private static readonly int[] Speeds = { 1, 3 };
    private static readonly string[] TowerKinds = { "thorn", "puff", "acorn" };
    private static readonly string[] TowerButtonPaths = { "HUD/Towers/ThornButton", "HUD/Towers/PuffButton", "HUD/Towers/AcornButton" };
    private static readonly StringName NextWaveAction = "next_wave";
    private static readonly StringName ToggleSpeedAction = "toggle_speed";

    private readonly Button[] _towerButtons = new Button[TowerKinds.Length];
    private Sprite2D _store = null!;
    private Label _mapLabel = null!;
    private Label _goldLabel = null!;
    private Label _livesLabel = null!;
    private Label _waveLabel = null!;
    private Label _infoLabel = null!;
    private Button _upgrade = null!;
    private Button _nextWave = null!;
    private Button _speedButton = null!;

    public Catalog Catalog { get; private set; } = null!;
    public Field Field { get; private set; } = null!;

    public Battle? battle { get; private set; }

    /// <summary>The map's place in the campaign, from 1.</summary>
    public int level { get; private set; } = 1;

    /// <summary>"playing" or "over".</summary>
    public string state { get; private set; } = "playing";

    /// <summary>The tower kind a click on an open cell builds.</summary>
    public string building { get; private set; } = "thorn";

    /// <summary>The cell of the tower whose upgrade the HUD offers; (-1, -1) for none.</summary>
    public Vector2I selected { get; private set; } = new(-1, -1);

    /// <summary>Battle ticks per physics tick.</summary>
    public int speed { get; set; } = 1;

    public int gold => battle?.Gold ?? 0;

    public int lives => battle?.Lives ?? 0;

    public int wave => battle?.Wave ?? 0;

    public string phase => battle?.PhaseName ?? "";

    public override void _Ready()
    {
        Field = GetNode<Field>("Field");
        _store = GetNode<Sprite2D>("Store");
        _mapLabel = GetNode<Label>("HUD/MapLabel");
        _goldLabel = GetNode<Label>("HUD/GoldLabel");
        _livesLabel = GetNode<Label>("HUD/LivesLabel");
        _waveLabel = GetNode<Label>("HUD/WaveLabel");
        _infoLabel = GetNode<Label>("HUD/InfoLabel");
        _upgrade = GetNode<Button>("HUD/UpgradeButton");
        _nextWave = GetNode<Button>("HUD/NextWaveButton");
        _speedButton = GetNode<Button>("HUD/SpeedButton");

        Catalog ??= Catalog.FromFiles();
        for (int i = 0; i < TowerKinds.Length; i++)
        {
            string id = TowerKinds[i];
            _towerButtons[i] = GetNode<Button>(TowerButtonPaths[i]);
            _towerButtons[i].Pressed += () => select_tower(id);
        }
        _upgrade.Pressed += () => upgrade_selected();
        _nextWave.Pressed += next_wave;
        _speedButton.Pressed += toggle_speed;
        start_map(1);
    }

    /// <summary>A new battle on the map at this place in the campaign, as start_map(index, -1).</summary>
    /// <remarks>An overload, not a default argument: the engine calls a C# method only with all its arguments.</remarks>
    public void start_map(int index) => start_map(index, -1);

    /// <summary>A new battle on the map at this place in the campaign; seed -1 draws one.</summary>
    public void start_map(int index, long seed)
    {
        MapRow? row = Catalog.MapAt(index);
        if (row == null)
        {
            GD.PushError($"There is no map {index}");
            return;
        }
        level = index;
        long battleSeed = seed >= 0 ? seed : GD.Randi() % 1000000;
        GD.Print($"[Run] map {index}, seed {battleSeed}");
        battle = Battle.Create(Catalog, row.Id, battleSeed)!;
        battle.TowerPlaced += _ => Refresh();
        battle.TowerUpgraded += _ => Refresh();
        battle.EnemyKilled += _ => Refresh();
        battle.EnemyLeaked += _ => Refresh();
        battle.WaveStarted += _ => Refresh();
        battle.WaveCleared += (_, _) => Refresh();
        battle.BattleOver += OnBattleOver;
        state = "playing";
        selected = new Vector2I(-1, -1);
        Field.ShowBattle(battle);
        _store.Position = Field.CellCentre(battle.Map.Store);
        Refresh();
    }

    private bool CanAct() => state == "playing" && !battle!.IsOver();

    public void select_tower(string id)
    {
        building = id;
        selected = new Vector2I(-1, -1);
        Refresh();
    }

    /// <summary>Builds the chosen kind on a cell, or selects the tower already there. For tests as well as clicks.</summary>
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
        if (state != "playing")
            return;
        for (int i = 0; i < speed; i++)
        {
            battle!.Step();
            if (battle.IsOver())
                break;
        }
        _waveLabel.Text = WaveText();
        Field.QueueRedraw();
    }

    private string WaveText()
    {
        if (battle!.Phase == Phase.Won)
            return "Map cleared";
        if (battle.Phase == Phase.Lost)
            return "The store is empty";
        if (battle.Phase == Phase.Build)
            return $"Wave {battle.Wave + 1} / {battle.Waves.Count} in {(int)Math.Ceiling(battle.BreakLeft / (double)Battle.TicksPerSecond)} s";
        return $"Wave {battle.Wave} / {battle.Waves.Count}";
    }

    private void OnBattleOver(bool won)
    {
        state = "over";
        GD.Print($"[Run] map {level} {(won ? "won" : "lost")}");
        Refresh();
    }

    private void Refresh()
    {
        if (battle == null || !IsNodeReady())
            return;
        _mapLabel.Text = "The Meadow";
        _goldLabel.Text = $"Sap: {battle.Gold}";
        _livesLabel.Text = $"Seeds: {battle.Lives}";
        _waveLabel.Text = WaveText();
        for (int i = 0; i < TowerKinds.Length; i++)
        {
            string id = TowerKinds[i];
            _towerButtons[i].Text = $"{id.Capitalize()}: {Catalog.Cost(id)}";
            _towerButtons[i].ButtonPressed = id == building;
        }
        bool hasSelection = battle.Towers.Has(selected);
        _upgrade.Disabled = !(hasSelection && battle.CanUpgrade(selected));
        _upgrade.Text = "Upgrade";
        if (hasSelection)
        {
            Tower tower = battle.Towers[selected];
            if (tower.Level < Catalog.MaxLevel(tower.Id))
                _upgrade.Text = $"Upgrade: {Catalog.UpgradeCost(tower.Id, tower.Level + 1)}";
            _infoLabel.Text = $"{tower.Id.Capitalize()}, level {tower.Level}";
        }
        else
        {
            _infoLabel.Text = "Pick a tower, then a cell.";
        }
        _nextWave.Disabled = battle.Phase != Phase.Build;
        _speedButton.Text = $"Speed x{speed}";
        Field.Selected = selected;
        Field.QueueRedraw();
    }
}
