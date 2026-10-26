namespace Wickerdeep.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// The bot and the balance it measures: seed 1's run reaches the bottom, and every floor is fair to a wick at full hp,
/// neither a wall nor a walk.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class BotTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    /// <summary>Plays a whole run as the game does: the stairs relight one hp. Returns the floor reached and how it ended.</summary>
    private (int Floor, bool Won, string Result) PlayRun(long seed)
    {
        var run = new Run(seed, Meta.BaseHp);
        for (int number = 1; number <= _floors.Count; number++)
        {
            run.FloorNumber = number;
            World world = World.Create(Dungeon.Generate(run.FloorSeed(), _floors.Spec(number)!), _floors.Kinds, run.FloorSeed(), run.Hp, run.MaxHp);
            string result = world.PlayOut(new Bot(), 7200);
            if (result != "cleared")
                return (number, false, result);
            run.Hp = System.Math.Min(world.Wick.Hp + 1, run.MaxHp);
        }
        return (_floors.Count, true, "cleared");
    }

    [TestCase]
    public void The_bot_reaches_the_bottom_with_seed_1()
    {
        (int floor, bool won, string result) = PlayRun(1);
        AssertThat(won).OverrideFailureMessage($"stopped on floor {floor}: {result}").IsTrue();
    }

    [TestCase]
    public void Every_floor_is_fair_to_a_wick_at_full_hp()
    {
        for (int number = 1; number <= _floors.Count; number++)
        {
            int cleared = 0;
            int lost = 0;
            for (int seed = 1; seed <= 20; seed++)
            {
                long seedOfFloor = seed * 1009 + number;
                World world = World.Create(Dungeon.Generate(seedOfFloor, _floors.Spec(number)!), _floors.Kinds, seedOfFloor, Meta.BaseHp, Meta.BaseHp);
                string result = world.PlayOut(new Bot(), 7200);
                AssertThat(result).OverrideFailureMessage($"floor {number} seed {seed}: the bot found nothing to do").IsNotEqual("stuck");
                if (result == "cleared")
                    cleared += 1;
                lost += Meta.BaseHp - world.Wick.Hp;
            }
            AssertThat(cleared).OverrideFailureMessage($"floor {number} cleared in {cleared} of 20").IsGreaterEqual(15);
            AssertThat(lost).OverrideFailureMessage($"floor {number} cost {lost} hp over 20 seeds: too easy").IsGreaterEqual(6);
        }
    }
}
