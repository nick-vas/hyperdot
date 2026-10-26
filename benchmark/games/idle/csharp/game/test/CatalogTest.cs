namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Catalog: the data the economy runs on, and the balance it promises.</summary>
[TestSuite]
[RequireGodotRuntime]
public class CatalogTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    [TestCase]
    public void Producers_come_in_price_order()
    {
        AssertThat(_catalog.Producers.Count).IsGreaterEqual(3);
        for (int i = 1; i < _catalog.Producers.Count; i++)
            AssertThat(_catalog.Producers[i].Cost).IsGreater(_catalog.Producers[i - 1].Cost);
    }

    [TestCase]
    public void Each_later_producer_takes_longer_to_pay_back()
    {
        double last = 0.0;
        foreach (ProducerData p in _catalog.Producers)
        {
            double payback = p.Cost / p.Rate;
            AssertThat(payback).OverrideFailureMessage(p.Id).IsGreater(last);
            last = payback;
        }
    }

    [TestCase]
    public void Every_upgrade_targets_something_that_exists()
    {
        foreach (UpgradeData u in _catalog.Upgrades)
            AssertThat(u.Target == "all" || u.Target == "tap" || _catalog.Producer(u.Target) != null).OverrideFailureMessage(u.Id).IsTrue();
    }

    [TestCase]
    public void The_economy_settings_are_there()
    {
        foreach (string id in new[] { "tap", "milestone_every", "milestone_multiplier", "dawn_base", "ember_bonus", "offline_cap_seconds", "autosave_seconds" })
            AssertThat(_catalog.Setting(id)).OverrideFailureMessage(id).IsGreater(0.0);
    }
}
