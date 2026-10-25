namespace Wickerdeep;

using System;
using System.Collections.Generic;
using Godot;

/// <summary>
/// One floor being played: the dungeon, the wick and the enemies, stepped one tick at a time by Step(). The rules and
/// the enemies' minds live here, not in nodes, so tests and the bot play whole floors without a scene, and a floor plays
/// the same from the same seed and the same inputs.
/// </summary>
/// <remarks>
/// Enemies wander until they see the wick (within their sight, no wall in between), then hunt it down the floor's one
/// distance field, which is searched again only when the wick changes cell: a hundred hunters cost one search, not a
/// hundred. Next to the wick (not diagonally) an enemy strikes, after a wind-up the wick can see coming.
/// </remarks>
public sealed class World
{
    public const int WickMoveTicks = 6;
    public const int WickAttackTicks = 14;
    /// <summary>Ticks after a hurt during which the wick cannot be hurt again.</summary>
    public const int MercyTicks = 30;
    /// <summary>Ticks an enemy goes on hunting after it loses sight of the wick.</summary>
    public const int MemoryTicks = 90;
    /// <summary>Ticks an enemy that has just come next to the wick waits before its first blow.</summary>
    public const int WindupTicks = 30;
    /// <summary>How long a swarm keeps hunting: for ever, in practice.</summary>
    public const int SwarmAlert = 1 << 30;

    public event Action<Actor>? EnemyHit;
    public event Action<Actor>? EnemySnuffed;
    public event Action<int>? WickHurt;
    /// <summary>The last enemy is gone: the stairs down are open.</summary>
    public event Action? StairsOpened;

    private readonly Dictionary<Vector2I, Actor> _occupied = new();
    private int[] _field = Array.Empty<int>();
    private Vector2I _fieldFrom = new(-1, -1);
    /// <summary>
    /// The enemies' own stream: wandering, and where a swarm appears. Not the generator's, so a change to how enemies
    /// wander never moves a room.
    /// </summary>
    private readonly RandomNumberGenerator _rng = new();

    private World(Dungeon dungeon, Actor wick)
    {
        Dungeon = dungeon;
        Wick = wick;
    }

    public Dungeon Dungeon { get; }
    public Actor Wick { get; }
    public List<Actor> Enemies { get; } = new();
    public int Tick { get; private set; }
    /// <summary>Embers gathered on this floor.</summary>
    public int Embers { get; set; }
    public bool StairsOpen { get; private set; }
    /// <summary>The wick stood on the open stairs: the floor is cleared.</summary>
    public bool Done { get; private set; }
    /// <summary>How many distance fields the enemies' hunting has searched, for the performance test.</summary>
    public int PathSearches { get; private set; }

    /// <summary>kinds: enemy id -> stats (Floors.Kinds). The wick starts on the dungeon's start with hp of maxHp.</summary>
    public static World Create(Dungeon dungeon, IReadOnlyDictionary<string, EnemyStats> kinds, long seed, int hp, int maxHp)
    {
        var wick = new Actor
        {
            Kind = "wick",
            Cell = dungeon.Start,
            FromCell = dungeon.Start,
            MaxHp = maxHp,
            Hp = Math.Clamp(hp, 1, maxHp),
            MoveTicks = WickMoveTicks,
            AttackTicks = WickAttackTicks,
        };
        var world = new World(dungeon, wick);
        world._rng.Seed = unchecked((ulong)(seed * 31 + 7));
        world._occupied[wick.Cell] = wick;
        foreach (Spawn spawn in dungeon.Spawns)
        {
            EnemyStats stats = kinds.TryGetValue(spawn.Kind, out EnemyStats? found) ? found : new EnemyStats { Id = spawn.Kind };
            world.AddEnemy(Actor.FromKind(stats, spawn.Cell));
        }
        world.StairsOpen = world.Enemies.Count == 0;
        return world;
    }

    public void AddEnemy(Actor enemy)
    {
        Enemies.Add(enemy);
        _occupied[enemy.Cell] = enemy;
    }

    /// <summary>Puts a creature on a cell at once, without a step: for tests and set-ups.</summary>
    public void Place(Actor actor, Vector2I cell)
    {
        if (_occupied.TryGetValue(actor.Cell, out Actor? there) && there == actor)
            _occupied.Remove(actor.Cell);
        actor.Cell = cell;
        actor.FromCell = cell;
        _occupied[cell] = actor;
    }

    /// <summary>count enemies of a kind, already hunting, on free floor cells at least 6 steps from the wick: the load for bench.</summary>
    public void AddSwarm(int count, EnemyStats stats)
    {
        int[] field = Dungeon.DistanceField(Wick.Cell);
        var cells = new List<Vector2I>();
        for (int y = 0; y < Dungeon.Height; y++)
        {
            for (int x = 0; x < Dungeon.Width; x++)
            {
                var cell = new Vector2I(x, y);
                if (field[Dungeon.Index(cell)] >= 6 && !_occupied.ContainsKey(cell) && cell != Dungeon.Stairs)
                    cells.Add(cell);
            }
        }
        for (int i = 0; i < Math.Min(count, cells.Count); i++)
        {
            int pick = _rng.RandiRange(i, cells.Count - 1);
            Vector2I cell = cells[pick];
            cells[pick] = cells[i];
            Actor bat = Actor.FromKind(stats, cell);
            bat.Alert = SwarmAlert;
            AddEnemy(bat);
        }
        StairsOpen = Enemies.Count == 0;
    }

    /// <summary>One tick: the wick acts on its input (move: one of Dungeon.Dirs or zero), then every enemy thinks.</summary>
    public void Step(Vector2I move, bool attack)
    {
        Tick += 1;
        Wick.MoveCooldown = Math.Max(Wick.MoveCooldown - 1, 0);
        Wick.AttackCooldown = Math.Max(Wick.AttackCooldown - 1, 0);
        Wick.Mercy = Math.Max(Wick.Mercy - 1, 0);
        if (Wick.Hp <= 0 || Done)
            return;
        if (attack && Wick.AttackCooldown == 0)
            Swing();
        if (move != Vector2I.Zero && Wick.MoveCooldown == 0)
        {
            Wick.Facing = move;
            if (CanEnter(Wick.Cell + move))
            {
                Move(Wick, Wick.Cell + move);
                Wick.MoveCooldown = WickMoveTicks;
            }
        }
        if (StairsOpen && Wick.Cell == Dungeon.Stairs)
        {
            Done = true;
            return;
        }
        // An enemy that wandered into the rock can never be reached: it is snuffed, so the floor can still be cleared.
        foreach (Actor enemy in new List<Actor>(Enemies))
        {
            if (!Dungeon.IsFloor(enemy.Cell))
                Snuff(enemy);
        }
        RefreshField();
        // Nothing is snuffed while the enemies think, so the list holds still.
        for (int i = 0; i < Enemies.Count; i++)
            Think(Enemies[i]);
    }

    private void Think(Actor enemy)
    {
        enemy.MoveCooldown = Math.Max(enemy.MoveCooldown - 1, 0);
        enemy.AttackCooldown = Math.Max(enemy.AttackCooldown - 1, 0);
        if (Sees(enemy))
            enemy.Alert = Math.Max(enemy.Alert, MemoryTicks);
        else if (enemy.Alert > 0)
            enemy.Alert -= 1;
        if (Adjacent(enemy.Cell, Wick.Cell))
        {
            if (enemy.AttackCooldown == 0)
            {
                HurtWick(enemy.Damage);
                enemy.AttackCooldown = enemy.AttackTicks;
            }
            return;
        }
        // Away from the wick it is never ready to strike at once: the wind-up starts when it arrives.
        enemy.AttackCooldown = Math.Max(enemy.AttackCooldown, WindupTicks);
        if (enemy.MoveCooldown > 0)
            return;
        enemy.MoveCooldown = enemy.MoveTicks;
        if (enemy.Alert > 0)
            Hunt(enemy);
        else
            Wander(enemy);
    }

    /// <summary>One step down the distance field towards the wick, to the free neighbour nearest it.</summary>
    private void Hunt(Actor enemy)
    {
        int[] field = _field;
        int here = Dungeon.InBounds(enemy.Cell) ? field[Dungeon.Index(enemy.Cell)] : -1;
        Vector2I best = enemy.Cell;
        int bestDistance = here >= 0 ? here : 1 << 30;
        foreach (Vector2I dir in Dungeon.Dirs)
        {
            Vector2I next = enemy.Cell + dir;
            if (!CanEnter(next))
                continue;
            int distance = field[Dungeon.Index(next)];
            if (distance >= 0 && distance < bestDistance)
            {
                bestDistance = distance;
                best = next;
            }
        }
        if (best != enemy.Cell)
            Move(enemy, best);
    }

    /// <summary>A step in a random direction, or none; walls and other creatures stop it.</summary>
    private void Wander(Actor enemy)
    {
        int roll = _rng.RandiRange(0, 5);
        if (roll >= Dungeon.Dirs.Length)
            return;
        Vector2I next = enemy.Cell + Dungeon.Dirs[roll];
        if (Dungeon.InBounds(next) && !_occupied.ContainsKey(next))
            Move(enemy, next);
    }

    /// <summary>The field the hunters follow, searched again only when the wick has moved.</summary>
    private void RefreshField()
    {
        if (Wick.Cell != _fieldFrom)
        {
            _field = Search(Wick.Cell);
            _fieldFrom = Wick.Cell;
        }
    }

    private int[] Search(Vector2I from)
    {
        PathSearches += 1;
        return Dungeon.DistanceField(from);
    }

    /// <summary>Whether an enemy sees the wick: within its sight (a circle) and no wall on the line between them.</summary>
    public bool Sees(Actor enemy)
    {
        Vector2I gap = Wick.Cell - enemy.Cell;
        if (gap.X * gap.X + gap.Y * gap.Y > enemy.Sight * enemy.Sight)
            return false;
        return Dungeon.LineClear(enemy.Cell, Wick.Cell);
    }

    /// <summary>Side by side, not diagonally.</summary>
    public static bool Adjacent(Vector2I a, Vector2I b) => Math.Abs(a.X - b.X) + Math.Abs(a.Y - b.Y) == 1;

    private bool CanEnter(Vector2I cell) => Dungeon.IsFloor(cell) && !_occupied.ContainsKey(cell);

    private void Move(Actor actor, Vector2I to)
    {
        _occupied.Remove(actor.Cell);
        actor.FromCell = actor.Cell;
        actor.MovedAt = Tick;
        actor.Cell = to;
        _occupied[to] = actor;
    }

    public Actor? EnemyAt(Vector2I cell) =>
        _occupied.TryGetValue(cell, out Actor? actor) && actor != Wick ? actor : null;

    /// <summary>The first enemy beside a cell, in the order of Dungeon.Dirs; null when there is none.</summary>
    public Actor? EnemyBeside(Vector2I cell)
    {
        foreach (Vector2I dir in Dungeon.Dirs)
        {
            Actor? enemy = EnemyAt(cell + dir);
            if (enemy != null)
                return enemy;
        }
        return null;
    }

    /// <summary>The wick's blow: the enemy it faces, else any enemy beside it.</summary>
    private void Swing()
    {
        Wick.AttackCooldown = WickAttackTicks;
        Actor? target = EnemyAt(Wick.Cell + Wick.Facing) ?? EnemyBeside(Wick.Cell);
        if (target == null)
            return;
        target.Hp -= Wick.Damage;
        target.HitAt = Tick;
        target.Alert = Math.Max(target.Alert, MemoryTicks);
        if (target.Hp <= 0)
            Snuff(target);
        else
            EnemyHit?.Invoke(target);
    }

    private void Snuff(Actor enemy)
    {
        Enemies.Remove(enemy);
        _occupied.Remove(enemy.Cell);
        Embers += enemy.Embers;
        EnemySnuffed?.Invoke(enemy);
        if (Enemies.Count == 0)
        {
            StairsOpen = true;
            StairsOpened?.Invoke();
        }
    }

    /// <summary>Takes hp from the wick, unless a hurt a moment ago still gives it mercy.</summary>
    public void HurtWick(int amount)
    {
        if (Wick.Mercy > 0 || Wick.Hp <= 0)
            return;
        Wick.Hp = Math.Max(Wick.Hp - amount, 0);
        Wick.Mercy = MercyTicks;
        WickHurt?.Invoke(amount);
    }

    /// <summary>Plays the floor with a bot in the wick's place: "cleared", "dead", or "stuck" after maxTicks.</summary>
    public string PlayOut(Bot bot, int maxTicks)
    {
        for (int i = 0; i < maxTicks; i++)
        {
            BotChoice choice = bot.Choose(this);
            Step(choice.Move, choice.Attack);
            if (Done)
                return "cleared";
            if (Wick.Hp <= 0)
                return "dead";
        }
        return "stuck";
    }
}
