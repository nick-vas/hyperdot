namespace Bramblegate;

using System;
using System.Collections;
using System.Collections.Generic;
using Godot;

public enum Phase
{
    Build,
    Wave,
    Won,
    Lost,
}

/// <summary>A tower on the field: its kind, its level and the ticks before it may fire again.</summary>
public sealed class Tower
{
    public Tower(Vector2I cell, string id)
    {
        Cell = cell;
        Id = id;
    }

    public Vector2I Cell { get; }
    public string Id { get; }
    public int Level { get; set; } = 1;
    public int Cooldown { get; set; }
}

/// <summary>The towers by cell, in the order they were built: the order they fire in.</summary>
public sealed class TowerSet : IEnumerable<Tower>
{
    private readonly List<Tower> _order = new();
    private readonly Dictionary<Vector2I, Tower> _byCell = new();

    public int Count => _order.Count;

    public Tower this[Vector2I cell] => _byCell[cell];

    public bool Has(Vector2I cell) => _byCell.ContainsKey(cell);

    public void Add(Tower tower)
    {
        _order.Add(tower);
        _byCell[tower.Cell] = tower;
    }

    public void Remove(Vector2I cell)
    {
        if (_byCell.Remove(cell, out Tower? tower))
            _order.Remove(tower);
    }

    public IEnumerator<Tower> GetEnumerator() => _order.GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}

/// <summary>A shot in the air, flying to its target, or to where it last aimed once the target has fallen.</summary>
public sealed class Shot
{
    public Vector2 Pos { get; set; }
    public Vector2 Aim { get; set; }
    public Enemy Target { get; set; } = null!;
    public int Damage { get; set; }
    /// <summary>Cells per tick.</summary>
    public double Speed { get; set; }
    public double Splash { get; set; }
    public double Slow { get; set; }
    /// <summary>The kind of tower that fired it.</summary>
    public string Tower { get; set; } = "";
}

/// <summary>
/// One map's battle, engine-light: the sap (gold), the seeds left in the store (lives), the towers, the pests, the shots
/// in the air and the waves. Step() advances it one tick, 60 to a second of play; the game node calls it and draws what
/// it holds, so tests and the bot play whole maps without a scene.
/// </summary>
/// <remarks>
/// A tick runs, in this order: the break before the next wave, spawns, pests walking, towers firing, shots flying, and
/// the end of the wave.
/// </remarks>
public sealed class Battle
{
    private static readonly string[] PhaseNames = { "Build", "Wave", "Won", "Lost" };
    public const int TicksPerSecond = 60;
    /// <summary>Ticks between the end of a wave (or the start of the map) and the next wave, unless it is called early.</summary>
    public const int BreakTicks = 600;
    /// <summary>What selling gives back, of everything the tower cost.</summary>
    public const double SellShare = 0.7;
    /// <summary>A tower with nothing in range looks again this many ticks later.</summary>
    public const int IdleTicks = 4;
    /// <summary>Each pest's speed varies by up to this share, from the battle's own generator.</summary>
    public const double SpeedJitter = 0.08;

    public event Action<int>? WaveStarted;
    public event Action<int, int>? WaveCleared;
    public event Action<Vector2I>? TowerPlaced;
    public event Action<Vector2I>? TowerUpgraded;
    public event Action<Vector2I, int>? TowerSold;
    public event Action<Vector2I>? ShotFired;
    public event Action<Enemy>? EnemyKilled;
    public event Action<Enemy>? EnemyLeaked;
    public event Action<bool>? BattleOver;

    private readonly List<Spawn> _spawns = new();
    private int _waveTick;
    private int _nextUid = 1;
    private readonly RandomNumberGenerator _rng = new();

    private Battle(Catalog catalog, PathMap map, string mapId)
    {
        Catalog = catalog;
        Map = map;
        MapId = mapId;
    }

    public Catalog Catalog { get; }
    public PathMap Map { get; }
    public string MapId { get; }
    public int Gold { get; set; }
    public int Lives { get; set; }
    public int StartLives { get; private set; }
    /// <summary>The wave under way, or the last one cleared; 0 before the first.</summary>
    public int Wave { get; private set; }
    public List<WaveRow> Waves { get; private set; } = new();
    public Phase Phase { get; set; } = Phase.Build;
    public int Ticks { get; private set; }
    public int BreakLeft { get; private set; } = BreakTicks;
    public TowerSet Towers { get; } = new();
    public List<Enemy> Enemies { get; } = new();
    public List<Shot> Shots { get; } = new();
    /// <summary>Every distance test towers made looking for a target: the performance tests read it.</summary>
    public int RangeChecks { get; private set; }
    public int Kills { get; private set; }
    public int Leaks { get; private set; }

    /// <summary>A battle on one of the catalog's maps, its pests' speeds drawn from seed; null when there is no such map.</summary>
    public static Battle? Create(Catalog catalog, string id, long seed)
    {
        MapRow? row = null;
        foreach (MapRow entry in catalog.Maps)
        {
            if (entry.Id == id)
                row = entry;
        }
        if (row == null)
        {
            GD.PushError($"Battle: there is no map {id}");
            return null;
        }
        return Custom(catalog, row.Rows, row.Gold, row.Lives, catalog.WavesFor(id), seed, id);
    }

    /// <summary>A battle on any rows of text (PathMap.FromRows), for tests and the bench.</summary>
    public static Battle Custom(Catalog catalog, IReadOnlyList<string> rows, int gold, int lives, List<WaveRow> waves, long seed = 1, string id = "custom")
    {
        var battle = new Battle(catalog, PathMap.FromRows(rows), id)
        {
            Gold = gold,
            Lives = lives,
            StartLives = lives,
            Waves = waves,
        };
        battle._rng.Seed = unchecked((ulong)seed);
        return battle;
    }

    public string PhaseName => PhaseNames[(int)Phase];

    public bool IsOver() => Phase == Phase.Won || Phase == Phase.Lost;

    // ---- Building ----

    /// <summary>
    /// Whether a tower of this kind may go on this cell now: enough sap, an open cell no pest stands on or is heading to,
    /// and the gate and every pest still with a way to the store.
    /// </summary>
    public bool CanPlace(string id, Vector2I cell)
    {
        if (IsOver() || !Catalog.HasTower(id) || Gold < Catalog.Cost(id))
            return false;
        if (!Map.IsBuildable(cell) || Towers.Has(cell) || Occupied(cell))
            return false;
        return !Map.Blocks(cell, EnemyTargets());
    }

    public bool Place(string id, Vector2I cell)
    {
        if (!CanPlace(id, cell))
            return false;
        Gold -= Catalog.Cost(id);
        Towers.Add(new Tower(cell, id));
        Map.SetTower(cell, true);
        Repath();
        TowerPlaced?.Invoke(cell);
        return true;
    }

    public bool CanUpgrade(Vector2I cell)
    {
        if (IsOver() || !Towers.Has(cell))
            return false;
        Tower tower = Towers[cell];
        int price = Catalog.UpgradeCost(tower.Id, tower.Level + 1);
        return tower.Level < Catalog.MaxLevel(tower.Id) && Gold >= price;
    }

    public bool Upgrade(Vector2I cell)
    {
        if (!CanUpgrade(cell))
            return false;
        Tower tower = Towers[cell];
        Gold -= Catalog.UpgradeCost(tower.Id, tower.Level + 1);
        tower.Level += 1;
        TowerUpgraded?.Invoke(cell);
        return true;
    }

    /// <summary>What selling the tower on this cell gives back: SellShare of its cost and of every upgrade bought for it.</summary>
    public int Refund(Vector2I cell)
    {
        if (!Towers.Has(cell))
            return 0;
        Tower tower = Towers[cell];
        int value = Catalog.Cost(tower.Id);
        for (int level = 2; level <= tower.Level; level++)
            value += Catalog.UpgradeCost(tower.Id, level);
        return (int)Math.Floor(value * SellShare);
    }

    /// <summary>Sells the tower on this cell; the pests take the shorter ways it opens. Returns the sap given back.</summary>
    public int Sell(Vector2I cell)
    {
        if (IsOver() || !Towers.Has(cell))
            return 0;
        int back = Refund(cell);
        Gold += back;
        Towers.Remove(cell);
        Map.SetTower(cell, false);
        Repath();
        TowerSold?.Invoke(cell, back);
        return back;
    }

    /// <summary>A pest stands on the cell or is heading to it.</summary>
    private bool Occupied(Vector2I cell)
    {
        foreach (Enemy enemy in Enemies)
        {
            if (enemy.Cell() == cell || enemy.Target() == cell)
                return true;
        }
        return false;
    }

    private List<Vector2I> EnemyTargets()
    {
        var cells = new List<Vector2I>();
        foreach (Enemy enemy in Enemies)
            cells.Add(enemy.Target());
        return cells;
    }

    /// <summary>Every pest takes the shortest way from the cell it is heading to, as the map now stands.</summary>
    private void Repath()
    {
        foreach (Enemy enemy in Enemies)
            enemy.Path = Map.PathFrom(enemy.Target());
    }

    // ---- Waves ----

    private sealed record Spawn(int Tick, string Enemy, int Order);

    /// <summary>Starts the next wave now, before its break is over; false when one is under way or none is left.</summary>
    public bool StartWave()
    {
        if (Phase != Phase.Build || Wave >= Waves.Count)
            return false;
        Wave += 1;
        Phase = Phase.Wave;
        _waveTick = Ticks;
        _spawns.Clear();
        int order = 0;
        foreach (GroupRow group in Waves[Wave - 1].Groups)
        {
            for (int i = 0; i < group.Count; i++)
            {
                _spawns.Add(new Spawn(group.Delay + i * group.Gap, group.Enemy, order));
                order += 1;
            }
        }
        _spawns.Sort((a, b) => a.Tick != b.Tick ? a.Tick.CompareTo(b.Tick) : a.Order.CompareTo(b.Order));
        GD.Print($"[Wave] {MapId} wave {Wave} of {Waves.Count}");
        WaveStarted?.Invoke(Wave);
        return true;
    }

    /// <summary>Puts a pest on a cell at once, outside any wave's schedule: for tests and the bench.</summary>
    public Enemy SpawnAt(string id, Vector2I cell)
    {
        Enemy enemy = AddEnemy(id);
        enemy.Pos = Enemy.Centre(cell);
        enemy.Path = Rest(Map.PathFrom(cell));
        return enemy;
    }

    /// <summary>The pests of the wave still to come.</summary>
    public int Pending() => _spawns.Count;

    public void Step()
    {
        if (IsOver())
            return;
        Ticks += 1;
        if (Phase == Phase.Build)
        {
            BreakLeft -= 1;
            if (BreakLeft <= 0)
                StartWave();
        }
        SpawnDue();
        Walk();
        if (IsOver())
            return;
        Fire();
        Fly();
        if (Phase == Phase.Wave && _spawns.Count == 0 && Enemies.Count == 0)
            ClearWave();
    }

    /// <summary>A path without its first cell: the way on from the cell a pest stands on.</summary>
    private static List<Vector2I> Rest(List<Vector2I> path) => path.Count > 1 ? path.GetRange(1, path.Count - 1) : new List<Vector2I>();

    private void SpawnDue()
    {
        while (_spawns.Count > 0 && _spawns[0].Tick <= Ticks - _waveTick)
        {
            Spawn due = _spawns[0];
            _spawns.RemoveAt(0);
            AddEnemy(due.Enemy);
        }
    }

    private Enemy AddEnemy(string id)
    {
        EnemyRow row = Catalog.Enemies[id];
        var enemy = new Enemy
        {
            Uid = _nextUid,
            Id = id,
            Hp = row.Hp,
            MaxHp = row.Hp,
            Speed = row.Speed * (1.0 + _rng.RandfRange((float)-SpeedJitter, (float)SpeedJitter)) / TicksPerSecond,
            Reward = row.Reward,
            Leak = row.Leak,
            Pos = Enemy.Centre(Map.Gate),
            Path = Rest(Map.Route),
        };
        _nextUid += 1;
        Enemies.Add(enemy);
        return enemy;
    }

    private void Walk()
    {
        var arrived = new List<Enemy>();
        foreach (Enemy enemy in Enemies)
        {
            double left = enemy.Pace();
            if (enemy.SlowTicks > 0)
                enemy.SlowTicks -= 1;
            while (left > 0.0 && enemy.Path.Count > 0)
            {
                Vector2I next = enemy.Path[0];
                // A pest never walks into a tower: it waits until it has a way.
                if (!Map.IsOpen(next))
                    break;
                Vector2 goal = Enemy.Centre(next);
                double gap = enemy.Pos.DistanceTo(goal);
                if (gap <= left)
                {
                    enemy.Pos = goal;
                    left -= gap;
                    enemy.Path.RemoveAt(0);
                }
                else
                {
                    // In 32-bit floats, as the engine's Vector2 does it for GDScript.
                    enemy.Pos += (goal - enemy.Pos) / (float)gap * (float)left;
                    left = 0.0;
                }
            }
            if (enemy.Path.Count == 0 && enemy.Cell() == Map.Store)
                arrived.Add(enemy);
        }
        foreach (Enemy enemy in arrived)
            LeakOut(enemy);
    }

    private void LeakOut(Enemy enemy)
    {
        enemy.Alive = false;
        Enemies.Remove(enemy);
        Leaks += 1;
        Lives = Math.Max(Lives - enemy.Leak, 0);
        EnemyLeaked?.Invoke(enemy);
        if (Lives == 0)
            End(false);
    }

    private void Fire()
    {
        foreach (Tower tower in Towers)
        {
            if (tower.Cooldown > 0)
            {
                tower.Cooldown -= 1;
                if (tower.Cooldown > 0)
                    continue;
            }
            TowerStats stats = Catalog.Stats(tower.Id, tower.Level);
            Enemy? enemy = TargetFor(tower.Cell, stats.Range);
            if (enemy == null)
            {
                tower.Cooldown = IdleTicks;
                continue;
            }
            Shots.Add(new Shot
            {
                Pos = Enemy.Centre(tower.Cell),
                Aim = enemy.Pos,
                Target = enemy,
                Damage = stats.Damage,
                Speed = stats.ShotSpeed / TicksPerSecond,
                Splash = stats.Splash,
                Slow = stats.Slow,
                Tower = tower.Id,
            });
            tower.Cooldown = stats.Reload;
            ShotFired?.Invoke(tower.Cell);
        }
    }

    /// <summary>The pest in range that is closest to the store along its way: towers shoot the one about to leak first.</summary>
    private Enemy? TargetFor(Vector2I cell, double reach)
    {
        Vector2 from = Enemy.Centre(cell);
        Enemy? best = null;
        double bestLeft = double.PositiveInfinity;
        foreach (Enemy enemy in Enemies)
        {
            RangeChecks += 1;
            if (enemy.Pos.DistanceSquaredTo(from) > reach * reach)
                continue;
            double left = enemy.Remaining();
            if (left < bestLeft)
            {
                best = enemy;
                bestLeft = left;
            }
        }
        return best;
    }

    private void Fly()
    {
        var landed = new List<Shot>();
        foreach (Shot shot in Shots)
        {
            if (shot.Target.Alive)
                shot.Aim = shot.Target.Pos;
            double gap = shot.Pos.DistanceTo(shot.Aim);
            if (gap <= shot.Speed)
            {
                shot.Pos = shot.Aim;
                landed.Add(shot);
            }
            else
            {
                shot.Pos += (shot.Aim - shot.Pos) / (float)gap * (float)shot.Speed;
            }
        }
        foreach (Shot shot in landed)
        {
            Shots.Remove(shot);
            Hit(shot);
        }
    }

    private void Hit(Shot shot)
    {
        if (shot.Splash <= 0.0)
        {
            if (shot.Target.Alive)
                Wound(shot.Target, shot.Damage, shot.Slow);
            return;
        }
        foreach (Enemy enemy in new List<Enemy>(Enemies))
        {
            if (enemy.Pos.DistanceTo(shot.Aim) <= shot.Splash)
                Wound(enemy, shot.Damage, shot.Slow);
        }
    }

    internal void Wound(Enemy enemy, int damage, double slow)
    {
        enemy.Hp -= damage;
        if (slow > 0.0)
        {
            enemy.Slow = slow;
            enemy.SlowTicks = Enemy.SlowTime;
        }
        if (enemy.Hp <= 0 && enemy.Alive)
        {
            enemy.Alive = false;
            Enemies.Remove(enemy);
            Kills += 1;
            Gold += enemy.Reward;
            EnemyKilled?.Invoke(enemy);
        }
    }

    private void ClearWave()
    {
        int bonus = Waves[Wave - 1].Bonus;
        Gold += bonus;
        GD.Print($"[Wave] {MapId} wave {Wave} cleared, bonus {bonus}");
        WaveCleared?.Invoke(Wave, bonus);
        if (Wave >= Waves.Count)
        {
            End(true);
            return;
        }
        Phase = Phase.Build;
        BreakLeft = BreakTicks;
    }

    private void End(bool won)
    {
        Phase = won ? Phase.Won : Phase.Lost;
        Shots.Clear();
        BattleOver?.Invoke(won);
    }
}
