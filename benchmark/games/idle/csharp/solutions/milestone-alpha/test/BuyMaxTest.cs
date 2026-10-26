namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Economy's bulk buys: ten at once, and as many as the glow pays for.</summary>
[TestSuite]
[RequireGodotRuntime]
public class BuyMaxTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void Max_is_zero_without_the_price_of_one()
    {
        _economy.Glow = 9.99;
        AssertThat(_economy.MaxAffordable("wick_moth")).IsEqual(0);
        AssertThat(_economy.BuyMax("wick_moth")).IsEqual(0);
    }

    [TestCase]
    public void Max_buys_as_many_as_the_glow_pays_for()
    {
        _economy.Glow = 100.0;
        int amount = _economy.MaxAffordable("wick_moth");
        AssertThat(amount).IsEqual(6);
        AssertThat(_economy.Cost("wick_moth", amount)).IsLessEqual(100.0);
        AssertThat(_economy.Cost("wick_moth", amount + 1)).IsGreater(100.0);
        AssertThat(_economy.BuyMax("wick_moth")).IsEqual(6);
        AssertThat(_economy.Count("wick_moth")).IsEqual(6);
    }

    [TestCase]
    public void Max_takes_the_last_one_at_an_exact_price()
    {
        _economy.SetCount("glow_snail", 12);
        _economy.Glow = _economy.Cost("glow_snail", 9);
        AssertThat(_economy.MaxAffordable("glow_snail")).IsEqual(9);
        _economy.BuyMax("glow_snail");
        AssertThat(_economy.Glow).IsEqual(0.0);
    }

    [TestCase]
    public void Max_with_a_vast_amount_of_glow()
    {
        _economy.Glow = 1e60;
        int amount = _economy.MaxAffordable("wick_moth");
        AssertThat(amount).IsBetween(900, 1000);
        AssertThat(_economy.Cost("wick_moth", amount)).IsLessEqual(1e60);
        AssertThat(_economy.Cost("wick_moth", amount + 1)).IsGreater(1e60);
    }
}
