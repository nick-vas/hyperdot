namespace Duskhive.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Hidden check for the alpha's add-content: the Star Loom, its upgrade, its name and its place in the balance.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenStarLoomTest
{
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load() => _catalog = Catalog.FromFiles();

    private int IndexOf(string id) => _catalog.Producers.FindIndex(p => p.Id == id);

    [TestCase]
    public void Hidden_the_star_loom_comes_after_the_moon_lily()
    {
        AssertThat(IndexOf("star_loom")).IsGreaterEqual(0);
        AssertThat(IndexOf("star_loom")).IsEqual(IndexOf("moon_lily") + 1);
        ProducerData p = _catalog.Producer("star_loom")!;
        AssertThat(p.Name).IsEqual("PRODUCER_STAR_LOOM");
        AssertThat(p.Cost).IsBetween(200000.0, 500000.0);
        AssertThat(p.Growth).IsBetween(1.10, 1.15);
    }

    [TestCase]
    public void Hidden_it_pays_back_slower_than_the_lily_but_not_twice_as_slow()
    {
        ProducerData lily = _catalog.Producer("moon_lily")!;
        ProducerData loom = _catalog.Producer("star_loom")!;
        double lilyPayback = lily.Cost / lily.Rate;
        double loomPayback = loom.Cost / loom.Rate;
        AssertThat(loomPayback).IsGreater(lilyPayback);
        AssertThat(loomPayback).IsLess(2.0 * lilyPayback);
    }

    [TestCase]
    public void Hidden_star_thread_doubles_it_at_ten()
    {
        UpgradeData? u = _catalog.Upgrade("star_thread");
        AssertThat(u != null).IsTrue();
        AssertThat(u!.Name).IsEqual("UPGRADE_STAR_THREAD");
        AssertThat(u.Target).IsEqual("star_loom");
        AssertThat(u.Multiplier).IsEqual(2.0);
        AssertThat(u.Needs).IsEqual(10);
        AssertThat(u.Cost).IsBetween(2e6, 1e7);
        var economy = new Economy(_catalog);
        economy.SetCount("star_loom", 10);
        economy.Glow = u.Cost;
        double before = economy.ProducerRate("star_loom");
        AssertThat(economy.BuyUpgrade("star_thread")).IsTrue();
        AssertThat(economy.ProducerRate("star_loom")).IsEqualApprox(before * 2.0, before * 1e-9);
    }

    [TestCase]
    public void Hidden_its_names_are_translated()
    {
        TranslationServer.SetLocale("en");
        AssertThat(TranslationServer.Translate("PRODUCER_STAR_LOOM").ToString()).IsEqual("Star Loom");
        AssertThat(TranslationServer.Translate("UPGRADE_STAR_THREAD").ToString()).IsEqual("Star Thread");
    }
}
