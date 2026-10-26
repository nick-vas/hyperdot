namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>The rule of the field: no tower may leave the gate, or a pest on the field, without a way to the store.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BlockingTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void The_last_gap_cannot_be_planted()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.#..", "..#..", "....G" }, 500, 5, new List<WaveRow>());
        AssertThat(battle.CanPlace("thorn", new Vector2I(2, 2))).IsFalse();
        AssertThat(battle.Place("thorn", new Vector2I(2, 2))).IsFalse();
        AssertThat(battle.Gold).IsEqual(500);
        AssertThat(battle.Map.Route).IsNotEmpty();
    }

    [TestCase]
    public void A_cell_with_a_way_round_it_can_be_planted()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S....", ".....", "....G" }, 500, 5, new List<WaveRow>());
        AssertThat(battle.Place("thorn", battle.Map.Route[2])).IsTrue();
    }

    [TestCase]
    public void A_wall_of_towers_always_leaves_a_gap()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.....", "......", "......", ".....G" }, 1000, 5, new List<WaveRow>());
        int planted = 0;
        for (int y = 0; y < 4; y++)
        {
            if (battle.Place("thorn", new Vector2I(3, y)))
                planted += 1;
        }
        AssertThat(planted).IsEqual(3);
        AssertThat(battle.Map.Route[^1]).IsEqual(battle.Map.Store);
    }
}
