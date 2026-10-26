namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: no tower may leave the gate, or any pest on the field, without a way to the
/// store; a cell with a way round it may still be planted, on the route or not.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBlockingTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Hidden_the_last_gap_is_refused()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.#..", "..#..", "....G" }, 500, 5, new List<WaveRow>());
        AssertThat(battle.CanPlace("thorn", new Vector2I(2, 2))).IsFalse();
        AssertThat(battle.Place("thorn", new Vector2I(2, 2))).IsFalse();
        AssertThat(battle.Gold).IsEqual(500);
        AssertThat(battle.Towers.Has(new Vector2I(2, 2))).IsFalse();
        AssertThat(battle.Map.Route).IsNotEmpty();
        AssertThat(battle.Map.Route[^1]).IsEqual(battle.Map.Store);
    }

    [TestCase]
    public void Hidden_a_route_cell_with_a_way_round_is_allowed()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S....", ".....", "....G" }, 500, 5, new List<WaveRow>());
        Vector2I cell = battle.Map.Route[2];
        AssertThat(battle.CanPlace("thorn", cell)).IsTrue();
        AssertThat(battle.Place("thorn", cell)).IsTrue();
        AssertThat(battle.Map.Route).NotContains(cell);
    }

    [TestCase]
    public void Hidden_a_wall_across_the_field_keeps_a_gap()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.....", "......", "......", ".....G" }, 1000, 5, new List<WaveRow>());
        int planted = 0;
        for (int y = 0; y < 4; y++)
        {
            if (battle.Place("thorn", new Vector2I(3, y)))
                planted += 1;
        }
        AssertThat(planted).IsEqual(3);
        AssertThat(battle.Map.Route).IsNotEmpty();
    }

    [TestCase]
    public void Hidden_a_pest_on_the_field_is_never_cut_off()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S....", "###..", "....G" }, 500, 5, new List<WaveRow>());
        Enemy pest = battle.SpawnAt("beetle", new Vector2I(0, 2));
        pest.Speed = 0.0;
        AssertThat(battle.Place("thorn", new Vector2I(3, 2))).OverrideFailureMessage("the corner the pest is in has no other way out").IsFalse();
        AssertThat(battle.Towers.Count).IsEqual(0);
        AssertThat(battle.Gold).IsEqual(500);
        AssertThat(pest.Path[^1]).IsEqual(battle.Map.Store);
    }

    [TestCase]
    public void Hidden_the_wave_still_ends_after_a_refused_tower()
    {
        var wave = new WaveRow("", 1, 0, new List<GroupRow> { new("aphid", 4, 20, 0) });
        Battle battle = Battle.Custom(_catalog, new[] { "S.#..", "..#..", "....G" }, 500, 20, new List<WaveRow> { wave });
        battle.StartWave();
        for (int i = 0; i < 60; i++)
            battle.Step();
        battle.Place("thorn", new Vector2I(2, 2));
        while (!battle.IsOver() && battle.Ticks < 3000)
            battle.Step();
        AssertThat(battle.Phase).IsEqual(Phase.Won);
        AssertThat(battle.Leaks).IsEqual(4);
    }
}
