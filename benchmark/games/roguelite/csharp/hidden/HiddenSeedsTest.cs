namespace Wickerdeep.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: a seed always builds the same floor, whatever the global generator did before;
/// seeds that differ build different floors; and generating leaves the global generator alone.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSeedsTest
{
    private Floors _floors = null!;

    [BeforeTest]
    public void Load()
    {
        _floors = Floors.FromFiles();
    }

    [TestCase]
    public void Hidden_the_same_seed_builds_the_same_floor_in_any_order()
    {
        for (int number = 1; number <= _floors.Count; number++)
        {
            string first = Dungeon.Generate(4242 + number, _floors.Spec(number)!).ToText();
            GD.Randomize();
            Dungeon.Generate(5, _floors.Spec(1)!);
            GD.Randomize();
            AssertThat(Dungeon.Generate(4242 + number, _floors.Spec(number)!).ToText()).OverrideFailureMessage($"floor {number}").IsEqual(first);
        }
    }

    [TestCase]
    public void Hidden_a_floor_plays_the_same_from_one_seed()
    {
        var texts = new List<string>();
        for (int attempt = 0; attempt < 2; attempt++)
        {
            GD.Randomize();
            World world = World.Create(Dungeon.Generate(77 * 1009 + 2, _floors.Spec(2)!), _floors.Kinds, 77 * 1009 + 2, 5, 5);
            var bot = new Bot();
            for (int i = 0; i < 600; i++)
            {
                BotChoice choice = bot.Choose(world);
                world.Step(choice.Move, choice.Attack);
            }
            texts.Add($"{world.Wick.Cell} {world.Wick.Hp} {world.Enemies.Count}");
        }
        AssertThat(texts[1]).IsEqual(texts[0]);
    }

    [TestCase]
    public void Hidden_seeds_that_differ_build_differently()
    {
        var seen = new HashSet<string>();
        for (int seed = 300; seed < 330; seed++)
            seen.Add(Dungeon.Generate(seed, _floors.Spec(2)!).ToText());
        AssertThat(seen.Count).IsEqual(30);
    }

    [TestCase]
    public void Hidden_generating_leaves_the_global_generator_alone()
    {
        GD.Seed(99);
        uint expected = GD.Randi();
        GD.Seed(99);
        Dungeon.Generate(7, _floors.Spec(1)!);
        World.Create(Dungeon.Generate(8, _floors.Spec(2)!), _floors.Kinds, 8, 5, 5);
        AssertThat(GD.Randi()).IsEqual(expected);
    }
}
