namespace Wickerdeep;

using Godot;

/// <summary>What the wick does this tick: a step of Dungeon.Dirs or zero, and whether it strikes.</summary>
public readonly record struct BotChoice(Vector2I Move, bool Attack);

/// <summary>
/// Plays the wick for --autoplay, the balance tests and the bot runs: strike whatever stands beside it, else walk the
/// shortest way to the nearest enemy it can reach, and once the stairs are open, walk to them. It reads only what a
/// player sees on screen and sends only what a player can press.
/// </summary>
public sealed class Bot
{
    public BotChoice Choose(World world)
    {
        Actor wick = world.Wick;
        if (world.EnemyBeside(wick.Cell) != null)
            return new BotChoice(Vector2I.Zero, true);
        if (wick.MoveCooldown > 0)
            return new BotChoice(Vector2I.Zero, false);
        Vector2I target = Target(world);
        if (target == wick.Cell)
            return new BotChoice(Vector2I.Zero, false);
        Dungeon dungeon = world.Dungeon;
        int[] field = dungeon.DistanceField(target);
        Vector2I best = Vector2I.Zero;
        int bestDistance = field[dungeon.Index(wick.Cell)];
        foreach (Vector2I dir in Dungeon.Dirs)
        {
            Vector2I next = wick.Cell + dir;
            if (!dungeon.IsFloor(next) || world.EnemyAt(next) != null)
                continue;
            int distance = field[dungeon.Index(next)];
            if (distance >= 0 && distance < bestDistance)
            {
                bestDistance = distance;
                best = dir;
            }
        }
        return new BotChoice(best, false);
    }

    /// <summary>The nearest enemy the wick can walk to, else the open stairs, else where it stands (nothing to do).</summary>
    private static Vector2I Target(World world)
    {
        Dungeon dungeon = world.Dungeon;
        int[] field = dungeon.DistanceField(world.Wick.Cell);
        Vector2I best = world.Wick.Cell;
        int bestDistance = 1 << 30;
        foreach (Actor enemy in world.Enemies)
        {
            if (!dungeon.InBounds(enemy.Cell))
                continue;
            int distance = field[dungeon.Index(enemy.Cell)];
            if (distance >= 0 && distance < bestDistance)
            {
                bestDistance = distance;
                best = enemy.Cell;
            }
        }
        if (world.Enemies.Count == 0 && world.StairsOpen)
            return dungeon.Stairs;
        return best;
    }
}
