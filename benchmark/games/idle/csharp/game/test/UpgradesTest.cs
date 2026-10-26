namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Upgrades: offered once their producer is owned often enough, they multiply it, the tap or everything.</summary>
[TestSuite]
[RequireGodotRuntime]
public class UpgradesTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start() => _economy = new Economy(Catalog.FromFiles());

    [TestCase]
    public void An_upgrade_waits_for_its_producer()
    {
        AssertThat(_economy.UpgradeUnlocked("twin_wicks")).IsFalse();
        _economy.SetCount("wick_moth", 10);
        AssertThat(_economy.UpgradeUnlocked("twin_wicks")).IsTrue();
    }

    [TestCase]
    public void An_upgrade_doubles_its_producer()
    {
        _economy.SetCount("wick_moth", 10);
        _economy.Glow = 150.0;
        double before = _economy.ProducerRate("wick_moth");
        AssertThat(_economy.BuyUpgrade("twin_wicks")).IsTrue();
        AssertThat(_economy.Glow).IsEqual(0.0);
        AssertThat(_economy.ProducerRate("wick_moth")).IsEqualApprox(before * 2.0, 1e-9);
        AssertThat(_economy.UpgradeUnlocked("twin_wicks")).OverrideFailureMessage("bought once").IsFalse();
    }

    [TestCase]
    public void Warm_hands_multiplies_gather()
    {
        _economy.Glow = 300.0;
        AssertThat(_economy.BuyUpgrade("warm_hands")).IsTrue();
        AssertThat(_economy.TapValue()).IsEqual(5.0);
    }

    [TestCase]
    public void Dusk_bloom_lifts_every_producer()
    {
        foreach (string id in new[] { "wick_moth", "glow_snail" })
            _economy.SetCount(id, 25);
        _economy.Glow = 1e6;
        double before = _economy.Rate();
        AssertThat(_economy.BuyUpgrade("dusk_bloom")).IsTrue();
        AssertThat(_economy.Rate()).IsEqualApprox(before * 1.5, 1e-6);
        AssertThat(_economy.TapValue()).OverrideFailureMessage("not the tap").IsEqual(1.0);
    }
}
