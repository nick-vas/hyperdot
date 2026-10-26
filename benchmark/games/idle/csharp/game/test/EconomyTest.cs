namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Economy: prices that grow by each producer's growth, buying, production over time and Gather.</summary>
[TestSuite]
[RequireGodotRuntime]
public class EconomyTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void The_first_of_a_producer_costs_its_base_price()
    {
        AssertThat(_economy.Cost("wick_moth")).IsEqual(10.0);
        AssertThat(_economy.Cost("glow_snail")).IsEqual(120.0);
    }

    [TestCase]
    public void Each_one_owned_raises_the_price_by_the_growth()
    {
        _economy.SetCount("wick_moth", 3);
        AssertThat(_economy.Cost("wick_moth")).IsEqualApprox(10.0 * 1.15 * 1.15 * 1.15, 1e-9);
    }

    [TestCase]
    public void Buying_spends_the_price_and_adds_one()
    {
        _economy.Glow = 25.0;
        AssertThat(_economy.Buy("wick_moth")).IsTrue();
        AssertThat(_economy.Count("wick_moth")).IsEqual(1);
        AssertThat(_economy.Glow).IsEqualApprox(15.0, 1e-9);
    }

    [TestCase]
    public void Too_little_glow_buys_nothing()
    {
        _economy.Glow = 9.0;
        AssertThat(_economy.Buy("wick_moth")).IsFalse();
        AssertThat(_economy.Count("wick_moth")).IsEqual(0);
        AssertThat(_economy.Glow).IsEqual(9.0);
    }

    [TestCase]
    public void An_unknown_producer_cannot_be_bought()
    {
        _economy.Glow = 1e9;
        AssertThat(_economy.Buy("lamp_post")).IsFalse();
    }

    [TestCase]
    public void Production_is_the_rate_times_the_seconds()
    {
        _economy.SetCount("wick_moth", 4);
        _economy.SetCount("glow_snail", 1);
        AssertThat(_economy.Rate()).IsEqualApprox(4 * 0.5 + 4.0, 1e-9);
        _economy.Tick(10.0);
        AssertThat(_economy.Glow).IsEqualApprox(60.0, 1e-9);
    }

    [TestCase]
    public void Every_25_of_a_producer_double_it()
    {
        _economy.SetCount("wick_moth", 25);
        AssertThat(_economy.ProducerRate("wick_moth")).IsEqualApprox(25 * 0.5 * 2.0, 1e-9);
    }

    [TestCase]
    public void Gather_gives_the_tap_value()
    {
        AssertThat(_economy.Tap()).IsEqual(1.0);
        AssertThat(_economy.Glow).IsEqual(1.0);
    }

    [TestCase]
    public void A_long_tick_and_many_short_ones_agree_within_the_tolerance()
    {
        _economy.SetCount("firefly_choir", 2000);
        var other = new Economy(_economy.Catalog);
        other.SetCount("firefly_choir", 2000);
        _economy.Tick(3600.0);
        for (int i = 0; i < 3600 * 4; i++)
            other.Tick(0.25);
        AssertThat(_economy.Glow).OverrideFailureMessage("past 2^53").IsGreater(9007199254740992.0);
        AssertThat(Numbers.Close(_economy.Glow, other.Glow, Numbers.Tolerance)).OverrideFailureMessage($"{_economy.Glow} and {other.Glow}").IsTrue();
    }

    [TestCase]
    public void Glow_stops_at_the_most_a_double_can_keep()
    {
        _economy.Earn(1e308);
        _economy.Earn(1e308);
        AssertThat(_economy.Glow).IsEqual(Numbers.Max);
        AssertThat(double.IsInfinity(_economy.Glow)).IsFalse();
    }
}
