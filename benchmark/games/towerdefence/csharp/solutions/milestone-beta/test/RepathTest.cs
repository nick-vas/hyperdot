namespace Bramblegate.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Pests on the field take a new tower into account at once: each turns onto the shortest way left from the cell it is
/// heading to, and none walks into a tower.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class RepathTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Pests_on_the_field_go_round_a_new_tower()
    {
        Battle battle = Battle.Custom(_catalog, new[] { "S.......", "........", ".......G" }, 500, 10, new List<WaveRow>());
        Enemy pest = battle.SpawnAt("beetle", new Vector2I(1, 0));
        pest.Hp = 100000;
        Vector2I ahead = pest.Path[3];
        AssertThat(battle.Place("thorn", ahead)).IsTrue();
        AssertThat(pest.Path).NotContains(ahead);
        AssertThat(pest.Path[^1]).IsEqual(battle.Map.Store);
        int lives = battle.Lives;
        bool entered = false;
        for (int i = 0; i < 1200; i++)
        {
            battle.Step();
            entered = entered || pest.Cell() == ahead;
            if (!pest.Alive)
                break;
        }
        AssertThat(entered).OverrideFailureMessage("it never stood on the tower's cell").IsFalse();
        AssertThat(battle.Lives).OverrideFailureMessage("it reached the store").IsEqual(lives - pest.Leak);
    }
}
