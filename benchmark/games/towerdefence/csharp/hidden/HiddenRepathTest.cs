namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: a placement turns every pest on the field at once onto the shortest way left
/// from the cell it is heading to; none walks up to the tower, and nothing searches paths without a placement.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRepathTest
{
    private static readonly string[] FieldRows = { "S.......", "........", ".......G" };

    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    private Battle NewBattle(int gold) => Battle.Custom(_catalog, FieldRows, gold, 10, new List<WaveRow>());

    private static Enemy Tough(Battle battle, Vector2I cell)
    {
        Enemy pest = battle.SpawnAt("beetle", cell);
        pest.Hp = 1000000;
        return pest;
    }

    [TestCase]
    public void Hidden_the_pests_turn_at_once()
    {
        Battle battle = NewBattle(500);
        Enemy pest = Tough(battle, new Vector2I(1, 0));
        Vector2I ahead = pest.Path[3];
        AssertThat(battle.Place("thorn", ahead)).IsTrue();
        AssertThat(pest.Path).OverrideFailureMessage("its way already goes round the tower").NotContains(ahead);
        AssertThat(pest.Path.Count).OverrideFailureMessage("the shortest way left").IsEqual(battle.Map.PathFrom(pest.Target()).Count);
        AssertThat(pest.Path[^1]).IsEqual(battle.Map.Store);
    }

    [TestCase]
    public void Hidden_a_pest_goes_round_and_reaches_the_store()
    {
        Battle battle = NewBattle(500);
        Enemy pest = Tough(battle, new Vector2I(1, 0));
        Vector2I ahead = pest.Path[2];
        int steps = battle.Map.PathFrom(pest.Target()).Count;
        battle.Place("thorn", ahead);
        double expected = (pest.Pos.DistanceTo(Enemy.Centre(pest.Target())) + (double)(battle.Map.PathFrom(pest.Target()).Count - 1)) / pest.Speed;
        int stood = 0;
        Vector2 last = pest.Pos;
        int ticks = 0;
        while (pest.Alive && ticks < 3000)
        {
            battle.Step();
            ticks += 1;
            if (pest.Alive)
            {
                stood += pest.Pos == last ? 1 : 0;
                last = pest.Pos;
            }
        }
        AssertThat(pest.Alive).IsFalse();
        AssertThat(battle.Leaks).OverrideFailureMessage("it reached the store").IsEqual(1);
        AssertThat(stood).OverrideFailureMessage("it never stood still").IsEqual(0);
        AssertThat((double)ticks).OverrideFailureMessage($"it took the way round at once ({steps} steps before)").IsLess(expected * 1.6 + 5.0);
    }

    [TestCase]
    public void Hidden_every_pest_on_the_field_turns()
    {
        Battle battle = NewBattle(500);
        var pests = new List<Enemy>();
        foreach (Vector2I cell in new[] { new Vector2I(0, 0), new Vector2I(1, 0), new Vector2I(0, 1), new Vector2I(2, 2) })
            pests.Add(Tough(battle, cell));
        AssertThat(battle.Place("thorn", new Vector2I(4, 1))).IsTrue();
        AssertThat(battle.Place("thorn", new Vector2I(5, 2))).IsTrue();
        foreach (Enemy pest in pests)
        {
            AssertThat(pest.Path).NotContains(new Vector2I(4, 1));
            AssertThat(pest.Path).NotContains(new Vector2I(5, 2));
            AssertThat(pest.Path.Count).IsEqual(battle.Map.PathFrom(pest.Target()).Count);
        }
    }

    [TestCase]
    public void Hidden_paths_are_searched_on_placements_only()
    {
        Battle battle = NewBattle(5000);
        for (int x = 0; x < 6; x++)
            Tough(battle, new Vector2I(x, 1));
        for (int i = 0; i < 10; i++)
            battle.Step();
        int before = battle.Map.PathQueries;
        for (int i = 0; i < 120; i++)
            battle.Step();
        AssertThat(battle.Map.PathQueries).OverrideFailureMessage("no placement, no search").IsEqual(before);
        before = battle.Map.PathQueries;
        AssertThat(battle.Place("thorn", new Vector2I(6, 0))).IsTrue();
        AssertThat(battle.Map.PathQueries - before).OverrideFailureMessage("one placement, a search or two per pest").IsLessEqual(2 * battle.Enemies.Count + 4);
    }
}
