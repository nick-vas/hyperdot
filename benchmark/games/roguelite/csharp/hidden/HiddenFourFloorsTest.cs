namespace Wickerdeep.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the alpha-to-beta milestone: four floors, the tallow brute, each floor whole and fair to the bot,
/// and saves from version 1.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenFourFloorsTest
{
    private string _path = "";
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"wickerdeep-hidden-four-{Guid.NewGuid():N}.json");
        _floors = Floors.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_four_floors_and_the_brute()
    {
        AssertThat(_floors.Count).IsEqual(4);
        EnemyStats brute = _floors.Kind("brute")!;
        AssertThat(brute.Hp).IsEqual(3);
        AssertThat(brute.Damage).IsEqual(2);
        AssertThat(brute.MoveTicks).IsGreater(_floors.Kind("shade")!.MoveTicks);
        foreach (int number in new[] { 3, 4 })
            AssertThat(_floors.Spec(number)!.Enemies).Contains("brute");
    }

    [TestCase]
    public void Hidden_every_floor_is_whole_and_fair()
    {
        for (int number = 1; number <= 4; number++)
        {
            int cleared = 0;
            int lost = 0;
            for (int seed = 1; seed <= 20; seed++)
            {
                long seedOfFloor = seed * 1009 + number;
                Dungeon dungeon = Dungeon.Generate(seedOfFloor, _floors.Spec(number)!);
                AssertThat(dungeon.UnreachableCells()).IsEqual(0);
                World world = World.Create(dungeon, _floors.Kinds, seedOfFloor, 5, 5);
                if (world.PlayOut(new Bot(), 7200) == "cleared")
                    cleared += 1;
                lost += 5 - world.Wick.Hp;
            }
            AssertThat(cleared).OverrideFailureMessage($"floor {number} cleared {cleared} of 20").IsGreaterEqual(15);
            AssertThat(lost).OverrideFailureMessage($"floor {number}").IsGreater(0);
        }
    }

    [TestCase]
    public void Hidden_a_version_1_save_loads()
    {
        File.WriteAllText(_path, """{"version": 1, "embers": 17, "best": 2}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Meta.Embers).IsEqual(17);
        AssertThat(data.Meta.BestFloor).IsEqual(2);
    }
}
