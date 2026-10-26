namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: towers choose their target without searching paths, so a field full of
/// pests costs no path search at all between placements; the leading pest in range is still the one shot.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenPathQueriesTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Hidden_a_full_field_searches_no_paths()
    {
        Battle battle = Battle.Create(_catalog, "meadow", 1)!;
        battle.Gold = 5000;
        battle.Lives = 100000;
        string[] kinds = { "thorn", "puff", "acorn" };
        int placed = 0;
        foreach (Vector2I cell in new[] { new Vector2I(2, 3), new Vector2I(4, 3), new Vector2I(6, 3), new Vector2I(8, 3), new Vector2I(10, 5), new Vector2I(12, 5), new Vector2I(5, 6), new Vector2I(9, 2) })
        {
            if (battle.Place(kinds[placed % 3], cell))
                placed += 1;
        }
        AssertThat(placed).IsGreaterEqual(6);
        string[] pests = { "aphid", "beetle" };
        for (int i = 0; i < 80; i++)
        {
            Enemy pest = battle.SpawnAt(pests[i % 2], battle.Map.Route[i % 8]);
            pest.Hp = 1000000;
        }
        int before = battle.Map.PathQueries;
        for (int i = 0; i < 300; i++)
            battle.Step();
        AssertThat(battle.Map.PathQueries - before).OverrideFailureMessage("path searches in 300 ticks with 80 pests and no placement").IsLessEqual(150);
        AssertThat(battle.Shots.Count + battle.RangeChecks).IsGreater(0);
    }

    [TestCase]
    public void Hidden_the_leading_pest_in_range_is_shot()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S..........G", "............" }, 500, 10, new List<WaveRow>());
        battle.Place("thorn", new Vector2I(5, 1));
        var pests = new List<Enemy>();
        foreach (int x in new[] { 2, 3, 4, 6, 7, 9 })
        {
            Enemy pest = battle.SpawnAt("beetle", new Vector2I(x, 0));
            pest.Speed = 0.0;
            pest.Hp = 1000;
            pests.Add(pest);
        }
        battle.Step();
        AssertThat(battle.Shots.Count).IsEqual(1);
        AssertThat(ReferenceEquals(battle.Shots[0].Target, pests[4])).OverrideFailureMessage("x = 7 is in range and closest to the store; x = 9 is out of range").IsTrue();
    }

    [TestCase]
    public void Hidden_the_target_is_the_one_furthest_along_its_own_way()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S...", "....", "...G" }, 500, 10, new List<WaveRow>());
        battle.Place("thorn", new Vector2I(1, 1));
        Enemy behind = battle.SpawnAt("beetle", new Vector2I(0, 2));
        Enemy ahead = battle.SpawnAt("beetle", new Vector2I(2, 2));
        ahead.Pos += new Vector2(0.3f, 0f);
        foreach (Enemy pest in new[] { behind, ahead })
        {
            pest.Speed = 0.0;
            pest.Hp = 1000;
        }
        battle.Step();
        AssertThat(ReferenceEquals(battle.Shots[0].Target, ahead)).OverrideFailureMessage("the pest ahead is shot").IsTrue();
    }
}
