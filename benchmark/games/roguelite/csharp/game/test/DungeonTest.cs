namespace Wickerdeep.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Dungeon: the generator's hard rules over a sweep of seeds, its seed, and the searches the enemies and the bot use.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DungeonTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    [TestCase]
    public void Every_floor_cell_is_reachable_from_the_start()
    {
        for (int number = 1; number <= _floors.Count; number++)
        {
            for (int seed = 1; seed <= 60; seed++)
            {
                Dungeon dungeon = Dungeon.Generate(seed * 1009 + number, _floors.Spec(number)!);
                AssertThat(dungeon.UnreachableCells()).OverrideFailureMessage($"floor {number}, seed {seed}").IsEqual(0);
            }
        }
    }

    [TestCase]
    public void Rooms_keep_a_wall_between_them_and_round_the_edge()
    {
        for (int seed = 1; seed <= 40; seed++)
        {
            Dungeon dungeon = Dungeon.Generate(seed, _floors.Spec(1)!);
            var whole = new Rect2I(1, 1, dungeon.Width - 2, dungeon.Height - 2);
            for (int i = 0; i < dungeon.Rooms.Count; i++)
            {
                AssertThat(whole.Encloses(dungeon.Rooms[i])).OverrideFailureMessage($"seed {seed} room {i} inside the edge").IsTrue();
                for (int j = i + 1; j < dungeon.Rooms.Count; j++)
                    AssertThat(dungeon.Rooms[i].Grow(1).Intersects(dungeon.Rooms[j])).OverrideFailureMessage($"seed {seed} rooms {i} and {j} apart").IsFalse();
            }
        }
    }

    [TestCase]
    public void Each_floor_has_its_rooms_and_enemies()
    {
        for (int number = 1; number <= _floors.Count; number++)
        {
            FloorSpec spec = _floors.Spec(number)!;
            for (int seed = 1; seed <= 20; seed++)
            {
                Dungeon dungeon = Dungeon.Generate(seed * 1009 + number, spec);
                AssertThat(dungeon.Rooms.Count).OverrideFailureMessage($"floor {number} seed {seed} rooms").IsBetween(spec.Rooms[0], spec.Rooms[1]);
                AssertThat(dungeon.Spawns.Count).OverrideFailureMessage($"floor {number} seed {seed} enemies").IsGreater(0);
                foreach (Spawn spawn in dungeon.Spawns)
                    AssertThat(spec.Enemies).Contains(spawn.Kind);
            }
        }
    }

    [TestCase]
    public void The_start_room_is_quiet_and_the_stairs_are_elsewhere()
    {
        for (int seed = 1; seed <= 40; seed++)
        {
            Dungeon dungeon = Dungeon.Generate(seed, _floors.Spec(1)!);
            AssertThat(dungeon.Rooms[0].HasPoint(dungeon.Start)).IsTrue();
            AssertThat(dungeon.Rooms[0].HasPoint(dungeon.Stairs)).OverrideFailureMessage($"seed {seed}").IsFalse();
            foreach (Spawn spawn in dungeon.Spawns)
            {
                AssertThat(dungeon.IsFloor(spawn.Cell)).IsTrue();
                AssertThat(dungeon.Rooms[0].HasPoint(spawn.Cell)).OverrideFailureMessage($"seed {seed}: an enemy in the start room").IsFalse();
                AssertThat(spawn.Cell != dungeon.Stairs).IsTrue();
            }
        }
    }

    [TestCase]
    public void The_same_seed_builds_the_same_floor()
    {
        string first = Dungeon.Generate(2026, _floors.Spec(1)!).ToText();
        string second = Dungeon.Generate(2026, _floors.Spec(1)!).ToText();
        AssertThat(second).IsEqual(first);
    }

    [TestCase]
    public void Seeds_that_differ_build_different_floors()
    {
        var seen = new HashSet<string>();
        for (int seed = 100; seed < 120; seed++)
            seen.Add(Dungeon.Generate(seed, _floors.Spec(1)!).ToText());
        AssertThat(seen.Count).IsEqual(20);
    }

    /// <summary>Seed 7 of floor 1, pinned: a change to the generator that moves it must say so here. The GDScript version builds the same floor.</summary>
    [TestCase]
    public void Seed_7_builds_the_pinned_floor()
    {
        Dungeon dungeon = Dungeon.Generate(7, _floors.Spec(1)!);
        AssertThat(dungeon.Rooms.Count).IsEqual(6);
        AssertThat(dungeon.Rooms[0] == new Rect2I(22, 9, 5, 4)).OverrideFailureMessage($"room 0 is {dungeon.Rooms[0]}").IsTrue();
        AssertThat(dungeon.Start).IsEqual(new Vector2I(24, 11));
        AssertThat(dungeon.Stairs).IsEqual(new Vector2I(10, 18));
        AssertThat(dungeon.FloorCells()).IsEqual(170);
        AssertThat(dungeon.Spawns.Count).IsEqual(8);
    }

    [TestCase]
    public void The_distance_field_counts_steps_round_walls()
    {
        Dungeon dungeon = Dungeon.FromText(
            "#######",
            "#S..#>#",
            "#.#.#.#",
            "#.#...#",
            "#######");
        int[] field = dungeon.DistanceField(dungeon.Start);
        AssertThat(field[dungeon.Index(new Vector2I(3, 1))]).IsEqual(2);
        AssertThat(field[dungeon.Index(dungeon.Stairs)]).IsEqual(8);
        AssertThat(field[dungeon.Index(new Vector2I(1, 3))]).IsEqual(2);
        AssertThat(field[dungeon.Index(new Vector2I(4, 1))]).OverrideFailureMessage("a wall").IsEqual(-1);
    }

    [TestCase]
    public void A_line_is_clear_only_over_floor()
    {
        Dungeon dungeon = Dungeon.FromText(
            "#######",
            "#.....#",
            "#..#..#",
            "#.....#",
            "#######");
        AssertThat(dungeon.LineClear(new Vector2I(1, 1), new Vector2I(5, 1))).IsTrue();
        AssertThat(dungeon.LineClear(new Vector2I(1, 2), new Vector2I(5, 2))).OverrideFailureMessage("the pillar is in the way").IsFalse();
        AssertThat(dungeon.LineClear(new Vector2I(1, 3), new Vector2I(5, 3))).IsTrue();
        AssertThat(dungeon.LineClear(new Vector2I(2, 2), new Vector2I(2, 2))).IsTrue();
    }
}
