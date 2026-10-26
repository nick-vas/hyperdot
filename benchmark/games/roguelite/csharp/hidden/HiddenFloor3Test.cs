namespace Wickerdeep.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's add-content: floor 3, The Drowned Nave, with the tallow brute, generated whole, and fair
/// to the bot at 5 hp.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFloor3Test
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
        TranslationServer.SetLocale("en");
    }

    [TestCase]
    public void Hidden_floor_3_is_in_the_data()
    {
        AssertThat(_floors.HasFloor(3)).IsTrue();
        FloorSpec spec = _floors.Spec(3)!;
        AssertThat(spec.Name).IsEqual("FLOOR_3");
        AssertThat(TranslationServer.Translate("FLOOR_3").ToString()).IsEqual("The Drowned Nave");
        AssertThat(spec.Width).IsEqual(44);
        AssertThat(spec.Height).IsEqual(26);
        AssertThat(spec.Rooms[0]).IsEqual(6);
        AssertThat(spec.Rooms[1]).IsEqual(8);
        foreach (string kind in new[] { "shade", "bat", "brute" })
            AssertThat(spec.Enemies).Contains(kind);
    }

    [TestCase]
    public void Hidden_the_brute_is_slow_and_heavy()
    {
        EnemyStats? brute = _floors.Kind("brute");
        AssertThat(brute).OverrideFailureMessage("a brute in data/enemies.json").IsNotNull();
        AssertThat(brute!.Name).IsEqual("ENEMY_BRUTE");
        AssertThat(TranslationServer.Translate("ENEMY_BRUTE").ToString()).IsEqual("Tallow brute");
        AssertThat(brute.Hp).IsEqual(3);
        AssertThat(brute.Damage).IsEqual(2);
        AssertThat(brute.Embers).IsEqual(3);
        AssertThat(brute.MoveTicks).IsGreater(_floors.Kind("shade")!.MoveTicks);
    }

    [TestCase]
    public void Hidden_floor_3_is_whole_and_has_brutes()
    {
        int withBrutes = 0;
        for (int seed = 1; seed <= 100; seed++)
        {
            Dungeon dungeon = Dungeon.Generate(seed * 1009 + 3, _floors.Spec(3)!);
            AssertThat(dungeon.UnreachableCells()).OverrideFailureMessage($"seed {seed}").IsEqual(0);
            foreach (Spawn spawn in dungeon.Spawns)
            {
                if (spawn.Kind == "brute")
                {
                    withBrutes += 1;
                    break;
                }
            }
        }
        AssertThat(withBrutes).OverrideFailureMessage($"brutes on {withBrutes} of 100 floors").IsGreater(60);
    }

    [TestCase]
    public void Hidden_floor_3_is_fair()
    {
        int cleared = 0;
        int lost = 0;
        for (int seed = 1; seed <= 20; seed++)
        {
            long seedOfFloor = seed * 1009 + 3;
            World world = World.Create(Dungeon.Generate(seedOfFloor, _floors.Spec(3)!), _floors.Kinds, seedOfFloor, 5, 5);
            if (world.PlayOut(new Bot(), 7200) == "cleared")
                cleared += 1;
            lost += 5 - world.Wick.Hp;
        }
        AssertThat(cleared).OverrideFailureMessage($"cleared {cleared} of 20").IsGreaterEqual(15);
        AssertThat(lost).OverrideFailureMessage($"it cost {lost} hp over 20 floors").IsGreaterEqual(10);
    }
}
