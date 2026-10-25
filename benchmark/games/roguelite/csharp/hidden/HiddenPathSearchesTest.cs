namespace Wickerdeep.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: a swarm hunting the wick costs one search of the floor per cell the wick
/// moves, not one per hunter's step; and the hunters still close in, round corners.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenPathSearchesTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    private World Swarmed()
    {
        World world = World.Create(Dungeon.Generate(7, _floors.Spec(1)!), _floors.Kinds, 7, 99, 99);
        world.AddSwarm(150, _floors.Kind("bat")!);
        return world;
    }

    [TestCase]
    public void Hidden_a_still_wick_costs_one_search()
    {
        World world = Swarmed();
        int[] field = world.Dungeon.DistanceField(world.Wick.Cell);
        var start = new Dictionary<Actor, int>();
        foreach (Actor enemy in world.Enemies)
            start[enemy] = field[world.Dungeon.Index(enemy.Cell)];
        for (int i = 0; i < 240; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(world.PathSearches).IsLessEqual(2);
        // The corridors jam a swarm, so not every hunter gains ground; many must.
        int closer = 0;
        int near = 0;
        foreach (Actor enemy in world.Enemies)
        {
            int distance = field[world.Dungeon.Index(enemy.Cell)];
            if (distance < start[enemy])
                closer += 1;
            if (distance <= 4)
                near += 1;
        }
        AssertThat(closer).OverrideFailureMessage($"{closer} hunters gained ground").IsGreaterEqual(40);
        AssertThat(near).OverrideFailureMessage($"{near} hunters within four steps").IsGreaterEqual(4);
    }

    [TestCase]
    public void Hidden_a_moving_wick_costs_a_search_per_cell()
    {
        World world = Swarmed();
        int moves = 0;
        Vector2I last = world.Wick.Cell;
        for (int i = 0; i < 240; i++)
        {
            Vector2I dir = Dungeon.Dirs[(i / 30) % 4];
            world.Step(dir, false);
            if (world.Wick.Cell != last)
            {
                moves += 1;
                last = world.Wick.Cell;
            }
        }
        AssertThat(world.PathSearches).OverrideFailureMessage($"{world.PathSearches} searches for {moves} moves").IsLessEqual(moves + 2);
    }

    [TestCase]
    public void Hidden_a_hunter_still_finds_the_way_round()
    {
        World world = World.Create(Dungeon.FromText(
            "#########",
            "#S......#",
            "#.#######",
            "#b......#",
            "#########"), _floors.Kinds, 1, 20, 20);
        for (int i = 0; i < World.WickMoveTicks * 6; i++)
            world.Step(Vector2I.Right, false);
        for (int i = 0; i < 200; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(World.Adjacent(world.Enemies[0].Cell, world.Wick.Cell)).IsTrue();
    }
}
