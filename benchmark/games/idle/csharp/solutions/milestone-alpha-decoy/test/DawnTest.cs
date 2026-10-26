namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>The dawn: embers for the square root of a run's glow, everything else reset, and each ember adding to production.</summary>
[TestSuite]
[RequireGodotRuntime]
public class DawnTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void No_dawn_before_a_million_glow_earned()
    {
        _economy.Earn(999999.0);
        AssertThat(_economy.CanDawn()).IsFalse();
        AssertThat(_economy.Dawn()).IsEqual(0.0);
    }

    [TestCase]
    public void The_gain_is_the_square_root_of_the_run_in_millions()
    {
        _economy.Earn(4e6);
        AssertThat(_economy.DawnGain()).IsEqual(2.0);
        _economy.Earn(5e6);
        AssertThat(_economy.DawnGain()).IsEqual(3.0);
    }

    [TestCase]
    public void A_dawn_resets_the_run_and_keeps_embers()
    {
        _economy.Earn(9e6);
        _economy.Buy("wick_moth");
        _economy.SetCount("glow_snail", 10);
        _economy.Upgrades.Add("warm_hands");
        AssertThat(_economy.Dawn()).IsEqual(3.0);
        AssertThat(_economy.Embers).IsEqual(3.0);
        AssertThat(_economy.Dawns).IsEqual(1);
        AssertThat(_economy.Glow).IsEqual(0.0);
        AssertThat(_economy.RunEarned).IsEqual(0.0);
        AssertThat(_economy.TotalEarned).IsEqual(9e6);
        AssertThat(_economy.Owned.Count).IsEqual(0);
        AssertThat(_economy.Upgrades.Count).IsEqual(0);
    }

    [TestCase]
    public void Each_ember_adds_a_tenth()
    {
        _economy.Embers = 5.0;
        _economy.SetCount("wick_moth", 2);
        AssertThat(_economy.Rate()).IsEqualApprox(2 * 0.5 * 1.5, 1e-9);
    }

    [TestCase]
    public void Spending_does_not_lower_the_dawn()
    {
        _economy.Earn(4e6);
        _economy.BuyMax("glow_snail");
        AssertThat(_economy.DawnGain()).IsEqual(2.0);
    }
}
