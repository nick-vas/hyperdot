namespace Duskhive.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: Buy max. The most a glow pays for, exactly at a price boundary and
/// with far more glow than a loop could count to, and the game's third buy mode.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBuyMaxTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void Hidden_nothing_without_the_price_of_one()
    {
        _economy.Glow = 9.99;
        AssertThat(_economy.MaxAffordable("wick_moth")).IsEqual(0);
        AssertThat(_economy.BuyMax("wick_moth")).IsEqual(0);
        AssertThat(_economy.Count("wick_moth")).IsEqual(0);
        AssertThat(_economy.Glow).IsEqual(9.99);
    }

    [TestCase]
    public void Hidden_the_most_the_glow_pays_for()
    {
        foreach (int owned in new[] { 0, 3, 30 })
        {
            foreach (double glow in new[] { 10.0, 99.0, 1234.5, 5e6 })
            {
                _economy.SetCount("wick_moth", owned);
                _economy.Glow = glow;
                int k = _economy.MaxAffordable("wick_moth");
                if (k > 0)
                    AssertThat(_economy.Cost("wick_moth", k)).OverrideFailureMessage($"{k} at {owned} owned with {glow}").IsLessEqual(glow);
                AssertThat(_economy.Cost("wick_moth", k + 1)).OverrideFailureMessage($"{k + 1} at {owned} owned with {glow}").IsGreater(glow);
            }
        }
    }

    [TestCase]
    public void Hidden_an_exact_price_buys_the_last_one()
    {
        foreach (int amount in new[] { 1, 2, 9, 17, 64 })
        {
            _economy.SetCount("glow_snail", 11);
            _economy.Glow = _economy.Cost("glow_snail", amount);
            AssertThat(_economy.MaxAffordable("glow_snail")).OverrideFailureMessage($"glow exactly the price of {amount}").IsEqual(amount);
        }
    }

    [TestCase]
    public void Hidden_vast_glow()
    {
        _economy.Glow = 1e80;
        int k = _economy.MaxAffordable("firefly_choir");
        AssertThat(k).IsGreater(1000);
        AssertThat(_economy.Cost("firefly_choir", k)).IsLessEqual(1e80);
        AssertThat(_economy.Cost("firefly_choir", k + 1)).IsGreater(1e80);
    }

    [TestCase]
    public void Hidden_buy_max_buys_and_spends_that_many()
    {
        _economy.SetCount("glow_snail", 4);
        _economy.Glow = 50000.0;
        int expected = _economy.MaxAffordable("glow_snail");
        double price = _economy.Cost("glow_snail", expected);
        AssertThat(_economy.BuyMax("glow_snail")).IsEqual(expected);
        AssertThat(_economy.Count("glow_snail")).IsEqual(4 + expected);
        AssertThat(_economy.Glow).IsEqualApprox(50000.0 - price, 1e-6);
    }

    [TestCase]
    public async Task Hidden_the_mode_button_offers_max()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        for (int i = 0; i < 2; i++)
            await game.ToSignal(game.GetTree(), SceneTree.SignalName.PhysicsFrame);
        var mode = game.GetNode<Button>("Safe/Column/Header/BuyModeButton");
        var seen = new List<int>();
        for (int i = 0; i < 3; i++)
        {
            seen.Add(game.buy_mode);
            mode.EmitSignal(BaseButton.SignalName.Pressed);
        }
        AssertThat(string.Join(",", seen)).IsEqual("1,10,0");
        AssertThat(game.buy_mode).OverrideFailureMessage("back to Buy 1 after Buy max").IsEqual(1);
        mode.EmitSignal(BaseButton.SignalName.Pressed);
        mode.EmitSignal(BaseButton.SignalName.Pressed);
        game.add_glow(1000.0);
        int expected = game.economy.MaxAffordable("wick_moth");
        game.GetNode("Safe/Column/ProducerPage/List/WickMothRow/Box/BuyButton").EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.economy.Count("wick_moth")).IsEqual(expected);
        AssertThat(expected).IsGreater(10);
    }
}
