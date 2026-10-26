namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Many pests and towers at once: every pest a tower shoots is in range, and the leading one is shot first.</summary>
[TestSuite]
[RequireGodotRuntime]
public class TargetingTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Every_shot_goes_to_a_pest_in_range()
    {
        Battle battle = Battle.Create(_catalog, "meadow", 3)!;
        battle.Gold = 2000;
        foreach (Vector2I cell in new[] { new Vector2I(3, 3), new Vector2I(6, 5), new Vector2I(9, 3), new Vector2I(12, 5) })
            battle.Place("thorn", cell);
        var bad = new List<Vector2I>();
        battle.ShotFired += cell =>
        {
            Shot shot = battle.Shots[^1];
            double reach = _catalog.Stats(battle.Towers[cell].Id, 1).Range;
            if (shot.Target.Pos.DistanceTo(Enemy.Centre(cell)) > reach + 0.001)
                bad.Add(cell);
        };
        battle.StartWave();
        for (int i = 0; i < 900; i++)
            battle.Step();
        AssertThat(battle.Kills).IsGreater(0);
        AssertThat(bad).IsEmpty();
    }

    [TestCase]
    public void The_leading_pest_is_shot_first()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S..........G", "............" }, 500, 10, new List<WaveRow>());
        AssertThat(battle.Place("thorn", new Vector2I(5, 1))).IsTrue();
        var pests = new List<Enemy>();
        foreach (int x in new[] { 3, 4, 6, 7 })
        {
            Enemy pest = battle.SpawnAt("beetle", new Vector2I(x, 0));
            pest.Speed = 0.0;
            pests.Add(pest);
        }
        battle.Step();
        AssertThat(ReferenceEquals(battle.Shots[0].Target, pests[3])).OverrideFailureMessage("the pest at x = 7 is shot").IsTrue();
    }
}
