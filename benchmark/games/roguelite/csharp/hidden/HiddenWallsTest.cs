namespace Wickerdeep.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: enemies never stand in the rock, wandering or hunting, on every floor and
/// many seeds; none vanishes without a blow; and the stairs stay sealed while one is left.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenWallsTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    [TestCase]
    public void Hidden_no_enemy_ever_stands_in_rock()
    {
        for (int number = 1; number <= _floors.Count; number++)
        {
            for (int seed = 1; seed <= 8; seed++)
            {
                long seedOfFloor = seed * 1009 + number;
                World world = World.Create(Dungeon.Generate(seedOfFloor, _floors.Spec(number)!), _floors.Kinds, seedOfFloor, 99, 99);
                int count = world.Enemies.Count;
                int inRock = 0;
                for (int i = 0; i < 900; i++)
                {
                    world.Step(Vector2I.Zero, false);
                    foreach (Actor enemy in world.Enemies)
                    {
                        if (!world.Dungeon.IsFloor(enemy.Cell))
                            inRock += 1;
                    }
                }
                AssertThat(inRock).OverrideFailureMessage($"floor {number} seed {seed}: enemies in the rock").IsEqual(0);
                AssertThat(world.Enemies.Count).OverrideFailureMessage($"floor {number} seed {seed}: enemies gone without a blow").IsEqual(count);
                AssertThat(world.StairsOpen).IsFalse();
            }
        }
    }

    [TestCase]
    public void Hidden_a_wanderer_walled_in_stays_put()
    {
        World world = World.Create(Dungeon.FromText(
            "#######",
            "#S#####",
            "#.##s##",
            "#>#####",
            "#######"), _floors.Kinds, 3, 5, 5);
        for (int i = 0; i < 600; i++)
            world.Step(Vector2I.Zero, false);
        AssertThat(world.Enemies[0].Cell).IsEqual(new Vector2I(4, 2));
    }

    [TestCase]
    public void Hidden_the_bot_clears_every_floor_of_seed_1()
    {
        var run = new Run(1, Meta.BaseHp);
        for (int number = 1; number <= _floors.Count; number++)
        {
            run.FloorNumber = number;
            World world = World.Create(Dungeon.Generate(run.FloorSeed(), _floors.Spec(number)!), _floors.Kinds, run.FloorSeed(), 9, 9);
            AssertThat(world.PlayOut(new Bot(), 7200)).OverrideFailureMessage($"floor {number}").IsEqual("cleared");
        }
    }
}
