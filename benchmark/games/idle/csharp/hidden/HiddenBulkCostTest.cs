namespace Duskhive.Tests;

using System.Collections.Generic;
using System.Threading.Tasks;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: a bulk price is the sum of the single prices it stands for, at every count
/// owned, and Buy 10 in the game spends exactly that.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenBulkCostTest
{
    private static double Singles(Economy economy, string id, int amount)
    {
        var copy = new Economy(economy.Catalog);
        foreach (KeyValuePair<string, int> owned in economy.Owned)
            copy.SetCount(owned.Key, owned.Value);
        copy.Glow = Numbers.Max;
        double total = 0.0;
        for (int i = 0; i < amount; i++)
        {
            total += copy.Cost(id, 1);
            copy.Buy(id, 1);
        }
        return total;
    }

    [TestCase]
    public void Hidden_a_bulk_price_is_the_sum_of_its_single_prices()
    {
        var economy = new Economy(Catalog.FromFiles());
        foreach (ProducerData p in economy.Catalog.Producers)
        {
            foreach (int owned in new[] { 0, 7, 40 })
            {
                economy.SetCount(p.Id, owned);
                foreach (int amount in new[] { 2, 10, 25 })
                {
                    double singles = Singles(economy, p.Id, amount);
                    AssertThat(Numbers.Close(economy.Cost(p.Id, amount), singles, 1e-9))
                        .OverrideFailureMessage($"{p.Id} x{amount} at {owned} owned: {economy.Cost(p.Id, amount)}, singles {singles}").IsTrue();
                }
            }
        }
    }

    [TestCase]
    public void Hidden_the_single_price_is_unchanged()
    {
        var economy = new Economy(Catalog.FromFiles());
        AssertThat(economy.Cost("glow_snail", 1)).IsEqual(120.0);
        economy.SetCount("glow_snail", 2);
        AssertThat(economy.Cost("glow_snail", 1)).IsEqualApprox(120.0 * 1.15 * 1.15, 1e-9);
    }

    [TestCase]
    public async Task Hidden_buy_10_spends_the_ten_single_prices()
    {
        using ISceneRunner runner = ISceneRunner.Load("res://game/game.tscn");
        var game = (Game)runner.Scene();
        for (int i = 0; i < 2; i++)
            await game.ToSignal(game.GetTree(), SceneTree.SignalName.PhysicsFrame);
        game.SetPhysicsProcess(false);
        double expected = Singles(game.economy, "glow_snail", 10);
        game.economy.Glow = expected;
        game.buy_mode = 10;
        game.Refresh();
        var button = game.GetNode<Button>("Safe/Column/ProducerPage/List/GlowSnailRow/Box/BuyButton");
        AssertThat(button.Disabled).OverrideFailureMessage("ten singles' worth of glow pays for Buy 10").IsFalse();
        button.EmitSignal(BaseButton.SignalName.Pressed);
        AssertThat(game.economy.Count("glow_snail")).IsEqual(10);
        AssertThat(game.economy.Glow).IsEqualApprox(0.0, expected * 1e-9);
    }
}
