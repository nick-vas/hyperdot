namespace Bramblegate;

using System.Collections.Generic;
using Godot;

/// <summary>
/// A player that builds by rule, for --autoplay and the balance tests: towers in a fixed order, each on the cell where
/// the route it leaves passes closest to it most often (so it builds a maze), then upgrades, the lowest level first. It
/// calls the next wave as soon as it has nothing to buy. Deterministic: the same battle gets the same build.
/// </summary>
public sealed class Bot
{
    private static readonly string[] Order = { "thorn", "thorn", "puff", "acorn" };
    public const int MaxTowers = 10;

    /// <summary>One decision: builds or upgrades at most one thing, or calls the next wave.</summary>
    public void Act(Battle battle)
    {
        if (battle.IsOver())
            return;
        if (battle.Towers.Count < MaxTowers)
        {
            string id = Order[battle.Towers.Count % Order.Length];
            if (battle.Gold >= battle.Catalog.Cost(id))
            {
                foreach (Vector2I cell in BestCells(battle, id))
                {
                    if (battle.Place(id, cell))
                        return;
                }
            }
            else
            {
                CallWave(battle);
                return;
            }
        }
        Tower? lowest = null;
        foreach (Tower tower in battle.Towers)
        {
            if (tower.Level < battle.Catalog.MaxLevel(tower.Id) && (lowest == null || tower.Level < lowest.Level))
                lowest = tower;
        }
        if (lowest != null && battle.Upgrade(lowest.Cell))
            return;
        CallWave(battle);
    }

    private static void CallWave(Battle battle)
    {
        if (battle.Phase == Phase.Build)
            battle.StartWave();
    }

    private sealed record Scored(Vector2I Cell, int Score, int Order);

    /// <summary>The cells a tower could go on, best first: how many cells of the route it would leave lie within its range.</summary>
    private static List<Vector2I> BestCells(Battle battle, string id)
    {
        double reach = battle.Catalog.Stats(id, 1).Range;
        var scored = new List<Scored>();
        for (int y = 0; y < battle.Map.Size.Y; y++)
        {
            for (int x = 0; x < battle.Map.Size.X; x++)
            {
                var cell = new Vector2I(x, y);
                if (!battle.Map.IsBuildable(cell) || !NearRoute(battle.Map.Route, cell, reach))
                    continue;
                List<Vector2I> route = battle.Map.PreviewRoute(cell);
                if (route.Count == 0)
                    continue;
                int covered = 0;
                foreach (Vector2I step in route)
                {
                    if (Enemy.Centre(step).DistanceSquaredTo(Enemy.Centre(cell)) <= reach * reach)
                        covered += 1;
                }
                scored.Add(new Scored(cell, covered, scored.Count));
            }
        }
        scored.Sort((a, b) => a.Score != b.Score ? b.Score.CompareTo(a.Score) : a.Order.CompareTo(b.Order));
        var cells = new List<Vector2I>();
        foreach (Scored entry in scored)
            cells.Add(entry.Cell);
        return cells;
    }

    private static bool NearRoute(List<Vector2I> route, Vector2I cell, double reach)
    {
        foreach (Vector2I step in route)
        {
            if (Enemy.Centre(step).DistanceSquaredTo(Enemy.Centre(cell)) <= reach * reach)
                return true;
        }
        return false;
    }

    /// <summary>Plays a battle to its end with this bot, for tests: true when it was won. Gives up after maxTicks.</summary>
    public static bool Play(Battle battle, int maxTicks = 60000)
    {
        var bot = new Bot();
        while (!battle.IsOver() && battle.Ticks < maxTicks)
        {
            bot.Act(battle);
            battle.Step();
        }
        return battle.Phase == Phase.Won;
    }

    /// <summary>Plays a battle to its end with no tower at all.</summary>
    public static bool Idle(Battle battle, int maxTicks = 60000)
    {
        while (!battle.IsOver() && battle.Ticks < maxTicks)
        {
            battle.StartWave();
            battle.Step();
        }
        return battle.Phase == Phase.Won;
    }
}
