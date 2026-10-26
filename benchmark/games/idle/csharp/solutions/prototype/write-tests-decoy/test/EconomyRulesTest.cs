namespace Duskhive.Tests;

using System;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Economy's rules: prices, purchases and production.</summary>
[TestSuite]
[RequireGodotRuntime]
public class EconomyRulesTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void A_price_grows_by_the_growth_for_each_one_owned()
    {
        AssertThat(_economy.Cost("glow_snail")).IsEqual(120.0);
        _economy.SetCount("glow_snail", 4);
        AssertThat(_economy.Cost("glow_snail")).IsEqualApprox(120.0 * Math.Pow(1.15, 4), 1e-9);
    }

    [TestCase]
    public void Several_cost_the_sum_of_their_single_prices()
    {
        _economy.SetCount("wick_moth", 3);
        double total = 0.0;
        for (int i = 0; i < 10; i++)
            total += 10.0 * Math.Pow(1.15, 3 + i);
        AssertThat(_economy.Cost("wick_moth", 10)).IsEqualApprox(total, total * 1e-12);
    }

    [TestCase]
    public void A_purchase_spends_its_price_and_adds_what_was_bought()
    {
        _economy.Glow = 1000.0;
        double price = _economy.Cost("wick_moth", 5);
        AssertThat(_economy.Buy("wick_moth", 5)).IsTrue();
        AssertThat(_economy.Count("wick_moth")).IsEqual(5);
        AssertThat(_economy.Glow).IsEqualApprox(1000.0 - price, 1e-9);
    }

    [TestCase]
    public void Nothing_is_bought_without_the_price()
    {
        _economy.Glow = 119.0;
        AssertThat(_economy.Buy("glow_snail")).IsFalse();
        AssertThat(_economy.Count("glow_snail")).IsEqual(0);
        AssertThat(_economy.Glow).IsEqual(119.0);
        _economy.Glow = 50.0;
        AssertThat(_economy.Buy("wick_moth", 5)).OverrideFailureMessage("five cost more than 50").IsFalse();
    }

    [TestCase]
    public void The_rate_is_each_producer_times_how_many()
    {
        _economy.SetCount("wick_moth", 3);
        _economy.SetCount("firefly_choir", 2);
        AssertThat(_economy.Rate()).IsEqualApprox(3 * 0.5 + 2 * 30.0, 1e-9);
    }

    [TestCase]
    public void A_tick_pays_the_rate_times_the_seconds()
    {
        _economy.SetCount("glow_snail", 2);
        AssertThat(_economy.Tick(2.5)).IsEqualApprox(20.0, 1e-9);
        AssertThat(_economy.Glow).IsEqualApprox(20.0, 1e-9);
    }
}
