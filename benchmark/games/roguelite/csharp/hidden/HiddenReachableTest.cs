namespace Wickerdeep.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: on every floor shape and hundreds of seeds, every room and every floor cell
/// can be reached from the start, found by a search of this test's own, and the rooms the floor rolled are all there.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenReachableTest
{
    private List<FloorSpec> _specs = null!;

    /// <summary>Floor 1 from the data, and the shapes of bigger floors the game will have.</summary>
    [BeforeTest]
    public void Load()
    {
        _specs = new List<FloorSpec>
        {
            Floors.FromFiles().Spec(1)!,
            new() { Width = 42, Height = 24, Rooms = new[] { 6, 7 }, RoomSize = new[] { 4, 7 }, Enemies = new List<string> { "shade" }, PerRoom = new[] { 1, 2 } },
            new() { Width = 44, Height = 26, Rooms = new[] { 7, 8 }, RoomSize = new[] { 4, 8 }, Enemies = new List<string> { "shade" }, PerRoom = new[] { 1, 3 } },
        };
    }

    private static HashSet<Vector2I> Reached(Dungeon dungeon)
    {
        var seen = new HashSet<Vector2I> { dungeon.Start };
        var stack = new Stack<Vector2I>();
        stack.Push(dungeon.Start);
        var steps = new[] { new Vector2I(0, -1), new Vector2I(1, 0), new Vector2I(0, 1), new Vector2I(-1, 0) };
        while (stack.Count > 0)
        {
            Vector2I cell = stack.Pop();
            foreach (Vector2I step in steps)
            {
                Vector2I next = cell + step;
                if (!seen.Contains(next) && next.X >= 0 && next.Y >= 0 && next.X < dungeon.Width && next.Y < dungeon.Height
                    && dungeon.Tiles[next.Y * dungeon.Width + next.X] == Dungeon.Floor)
                {
                    seen.Add(next);
                    stack.Push(next);
                }
            }
        }
        return seen;
    }

    [TestCase]
    public void Hidden_every_room_and_cell_is_reachable()
    {
        var failures = new List<string>();
        for (int s = 0; s < _specs.Count; s++)
        {
            for (int seed = 1; seed <= 300; seed++)
            {
                Dungeon dungeon = Dungeon.Generate(seed * 7 + s, _specs[s]);
                HashSet<Vector2I> seen = Reached(dungeon);
                int floorCount = 0;
                foreach (byte tile in dungeon.Tiles)
                {
                    if (tile == Dungeon.Floor)
                        floorCount += 1;
                }
                int lost = 0;
                foreach (Rect2I room in dungeon.Rooms)
                {
                    for (int y = room.Position.Y; y < room.End.Y; y++)
                    {
                        for (int x = room.Position.X; x < room.End.X; x++)
                        {
                            if (!seen.Contains(new Vector2I(x, y)))
                                lost += 1;
                        }
                    }
                }
                if (seen.Count != floorCount || lost > 0)
                    failures.Add($"shape {s} seed {seed * 7 + s}");
            }
        }
        AssertThat(failures.Count).OverrideFailureMessage(string.Join(", ", failures.GetRange(0, System.Math.Min(10, failures.Count)))).IsEqual(0);
    }

    [TestCase]
    public void Hidden_the_rooms_rolled_are_all_there()
    {
        for (int s = 0; s < _specs.Count; s++)
        {
            for (int seed = 1; seed <= 100; seed++)
            {
                Dungeon dungeon = Dungeon.Generate(seed, _specs[s]);
                AssertThat(dungeon.Rooms.Count).OverrideFailureMessage($"shape {s} seed {seed}").IsGreaterEqual(_specs[s].Rooms[0]);
                foreach (Spawn spawn in dungeon.Spawns)
                    AssertThat((int)dungeon.Tiles[dungeon.Index(spawn.Cell)]).OverrideFailureMessage("an enemy on rock").IsEqual((int)Dungeon.Floor);
            }
        }
    }

    [TestCase]
    public void Hidden_the_stairs_and_every_enemy_can_be_reached()
    {
        for (int seed = 1; seed <= 200; seed++)
        {
            Dungeon dungeon = Dungeon.Generate(seed * 1009 + 1, _specs[0]);
            HashSet<Vector2I> seen = Reached(dungeon);
            AssertThat(seen.Contains(dungeon.Stairs)).OverrideFailureMessage($"seed {seed} stairs").IsTrue();
            foreach (Spawn spawn in dungeon.Spawns)
                AssertThat(seen.Contains(spawn.Cell)).OverrideFailureMessage($"seed {seed}: an enemy at {spawn.Cell}").IsTrue();
        }
    }
}
