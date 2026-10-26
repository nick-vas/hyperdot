namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>PathMap: the route from the gate to the store, rocks and towers in its way, and what a tower would block.</summary>
[TestSuite]
[RequireGodotRuntime]
public class PathMapTest
{
    private static readonly string[] FieldRows =
    {
        "S.#.....",
        "..#.##..",
        "....#..G",
    };

    [TestCase]
    public void The_route_runs_from_the_gate_to_the_store()
    {
        PathMap map = PathMap.FromRows(FieldRows);
        AssertThat(map.Route[0]).IsEqual(new Vector2I(0, 0));
        AssertThat(map.Route[^1]).IsEqual(new Vector2I(7, 2));
        AssertThat(map.Route.Count).OverrideFailureMessage("the shortest way round the rocks").IsEqual(14);
    }

    [TestCase]
    public void Rocks_are_never_on_the_route()
    {
        PathMap map = PathMap.FromRows(FieldRows);
        foreach (Vector2I cell in map.Route)
            AssertThat(map.IsRock(cell)).IsFalse();
    }

    [TestCase]
    public void A_tower_moves_the_route_and_selling_it_restores_it()
    {
        PathMap map = PathMap.FromRows(new[] { "S...G", ".....", "....." });
        AssertThat(map.Route.Count).IsEqual(5);
        map.SetTower(new Vector2I(2, 0), true);
        AssertThat(map.Route).NotContains(new Vector2I(2, 0));
        AssertThat(map.Route.Count).IsEqual(7);
        map.SetTower(new Vector2I(2, 0), false);
        AssertThat(map.Route.Count).IsEqual(5);
    }

    [TestCase]
    public void The_gate_and_the_store_cannot_be_built_on()
    {
        PathMap map = PathMap.FromRows(FieldRows);
        AssertThat(map.IsBuildable(map.Gate)).IsFalse();
        AssertThat(map.IsBuildable(map.Store)).IsFalse();
        AssertThat(map.IsBuildable(new Vector2I(2, 0))).OverrideFailureMessage("a rock").IsFalse();
        AssertThat(map.IsBuildable(new Vector2I(1, 0))).IsTrue();
    }

    [TestCase]
    public void A_tower_in_the_last_gap_blocks()
    {
        PathMap map = PathMap.FromRows(new[] { "S.#..", "..#..", "....G" });
        AssertThat(map.Blocks(new Vector2I(2, 2), new List<Vector2I>())).IsTrue();
        AssertThat(map.Blocks(new Vector2I(1, 1), new List<Vector2I>())).IsFalse();
    }

    [TestCase]
    public void A_tower_that_cuts_a_cell_off_blocks_it()
    {
        PathMap map = PathMap.FromRows(new[] { "S....", "###..", "....G" });
        AssertThat(map.Blocks(new Vector2I(3, 2), new List<Vector2I>())).IsFalse();
        AssertThat(map.Blocks(new Vector2I(3, 2), new List<Vector2I> { new(1, 2) })).OverrideFailureMessage("the corner beyond it has no other way out").IsTrue();
    }

    [TestCase]
    public void Checks_leave_the_map_as_it_was()
    {
        PathMap map = PathMap.FromRows(FieldRows);
        var before = new List<Vector2I>(map.Route);
        map.Blocks(new Vector2I(3, 2), new List<Vector2I>());
        map.PreviewRoute(new Vector2I(3, 2));
        AssertThat(map.Route).ContainsExactly(before);
        AssertThat(map.IsOpen(new Vector2I(3, 2))).IsTrue();
        AssertThat(map.PathFrom(map.Gate)).ContainsExactly(before);
    }

    [TestCase]
    public void A_path_from_a_rock_is_empty()
    {
        PathMap map = PathMap.FromRows(FieldRows);
        AssertThat(map.PathFrom(new Vector2I(2, 0))).IsEmpty();
    }
}
