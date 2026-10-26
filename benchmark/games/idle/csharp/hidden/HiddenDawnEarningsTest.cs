namespace Duskhive.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-playthrough: everything the hive makes counts toward the dawn and toward the glow
/// earned in all runs, spending never lowers the dawn, and the dawn is no cheaper than before.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenDawnEarningsTest
{
    private Economy _economy = null!;

    [BeforeTest]
    public void Start()
    {
        _economy = new Economy(Catalog.FromFiles());
        _economy.SetCount("moon_lily", 20);
    }

    [TestCase]
    public void Hidden_production_counts_toward_the_dawn()
    {
        double made = _economy.Tick(1000.0);
        AssertThat(made).IsGreater(0.0);
        AssertThat(_economy.RunEarned).IsEqualApprox(made, made * 1e-12);
        AssertThat(_economy.TotalEarned).IsEqualApprox(made, made * 1e-12);
    }

    [TestCase]
    public void Hidden_time_away_counts_toward_the_dawn()
    {
        TimeAway away = Offline.Apply(_economy, 0.0, 7200.0);
        AssertThat(_economy.RunEarned).IsEqualApprox(away.Glow, 1e-6);
        AssertThat(_economy.TotalEarned).IsEqualApprox(away.Glow, 1e-6);
    }

    [TestCase]
    public void Hidden_spending_does_not_lower_the_dawn()
    {
        _economy.Tick(1000.0);
        double gain = _economy.DawnGain();
        AssertThat(gain).IsGreaterEqual(1.0);
        _economy.BuyMax("star_loom");
        _economy.BuyMax("moon_lily");
        AssertThat(_economy.DawnGain()).IsEqual(gain);
    }

    [TestCase]
    public void Hidden_the_dawn_costs_what_it_did()
    {
        var fresh = new Economy(Catalog.FromFiles());
        fresh.Earn(999999.0);
        AssertThat(fresh.DawnGain()).IsEqual(0.0);
        fresh.Earn(1.0);
        AssertThat(fresh.DawnGain()).IsEqual(1.0);
        fresh.Earn(8e6);
        AssertThat(fresh.DawnGain()).IsEqual(3.0);
    }

    [TestCase]
    public void Hidden_the_bot_greets_three_dawns_within_an_hour()
    {
        var bot = new Economy(Catalog.FromFiles());
        for (int second = 0; second < 3600; second++)
        {
            Bot.Act(bot);
            bot.Tick(1.0);
        }
        AssertThat(bot.Dawns).IsGreaterEqual(3);
        AssertThat(bot.Dawns).OverrideFailureMessage("not trivial").IsLess(12);
    }
}
