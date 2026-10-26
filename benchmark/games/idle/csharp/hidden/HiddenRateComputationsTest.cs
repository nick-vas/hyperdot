namespace Duskhive.Tests;

using System.Text.Json.Nodes;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: the rate is worked out once per change, not every tick, and is still
/// right at once after every kind of change.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenRateComputationsTest
{
    private static async Task PhysicsFrames(Node node, int count)
    {
        for (int i = 0; i < count; i++)
            await node.ToSignal(node.GetTree(), SceneTree.SignalName.PhysicsFrame);
    }

    /// <summary>The game scene with 30 of every producer.</summary>
    private static async Task<Game> Start(ISceneRunner runner)
    {
        var game = (Game)runner.Scene();
        await PhysicsFrames(game, 2);
        foreach (ProducerData p in game.economy.Catalog.Producers)
            game.economy.SetCount(p.Id, 30);
        return game;
    }

    private static double Expected(Economy economy)
    {
        double total = 0.0;
        foreach (ProducerData p in economy.Catalog.Producers)
            total += economy.UnitRate(p.Id) * economy.Count(p.Id);
        return total;
    }

    [TestCase]
    public async Task Hidden_ticks_alone_work_nothing_out_again()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await PhysicsFrames(game, 2);
        int before = game.economy.RateComputations;
        await PhysicsFrames(game, 600);
        AssertThat(game.economy.RateComputations - before).IsLessEqual(1);
    }

    [TestCase]
    public async Task Hidden_a_purchase_works_it_out_once_or_twice()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        await PhysicsFrames(game, 2);
        game.add_glow(1e9);
        int before = game.economy.RateComputations;
        game.buy("glow_snail");
        await PhysicsFrames(game, 30);
        AssertThat(game.economy.RateComputations - before).IsBetween(1, 2);
    }

    [TestCase]
    public async Task Hidden_the_rate_is_right_at_once_after_a_purchase()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Economy economy = game.economy;
        economy.Rate();
        economy.Glow = 1e12;
        double rateBefore = economy.Rate();
        economy.Buy("star_loom");
        AssertThat(economy.Rate()).IsGreater(rateBefore);
        AssertThat(Numbers.Close(economy.Rate(), Expected(economy), 1e-9)).IsTrue();
        double earned = economy.Tick(1.0);
        AssertThat(Numbers.Close(earned, Expected(economy), 1e-9)).OverrideFailureMessage("the next tick pays the new rate").IsTrue();
    }

    [TestCase]
    public async Task Hidden_the_rate_is_right_at_once_after_an_upgrade_and_a_dawn()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Economy economy = game.economy;
        economy.Rate();
        economy.Glow = 1e12;
        AssertThat(economy.BuyUpgrade("twin_wicks")).IsTrue();
        AssertThat(Numbers.Close(economy.ProducerRate("wick_moth"), 0.5 * 30 * 2.0 * 2.0, 1e-9)).IsTrue();
        economy.Earn(4e6);
        economy.Dawn();
        AssertThat(economy.Rate()).IsEqual(0.0);
        AssertThat(economy.Tick(10.0)).IsEqual(0.0);
    }

    [TestCase]
    public async Task Hidden_a_loaded_economy_starts_with_its_rate()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        Game game = await Start(runner);
        Economy economy = Economy.FromDict(game.economy.Catalog, new JsonObject { ["owned"] = new JsonObject { ["glow_snail"] = 5 } });
        AssertThat(economy.Tick(2.0)).IsEqualApprox(40.0, 1e-9);
        int before = economy.RateComputations;
        for (int i = 0; i < 1000; i++)
            economy.Tick(1.0 / 60.0);
        AssertThat(economy.RateComputations - before).IsLessEqual(1);
    }
}
