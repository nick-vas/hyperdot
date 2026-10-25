namespace Wickerdeep.Tests;

using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Meta: embers banked across runs, vigor bought with them, the deepest floor and the runs counted.</summary>
[TestSuite]
public class MetaTest
{
    [TestCase]
    public void A_won_run_banks_every_ember()
    {
        var save = new SaveData();
        Meta.Bank(save, 7, 4, true);
        AssertThat(save.Meta.Embers).IsEqual(7);
        AssertThat(save.Meta.BestFloor).IsEqual(4);
        AssertThat(save.Meta.Runs).IsEqual(1);
    }

    [TestCase]
    public void A_death_banks_half_the_embers()
    {
        var save = new SaveData();
        Meta.Bank(save, 7, 2, false);
        AssertThat(save.Meta.Embers).IsEqual(3);
    }

    [TestCase]
    public void Vigor_costs_embers_and_adds_hp()
    {
        var save = new SaveData();
        save.Meta.Embers = 16;
        AssertThat(Meta.MaxHp(save)).IsEqual(Meta.BaseHp);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        AssertThat(save.Meta.Embers).IsEqual(11);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        AssertThat(save.Meta.Embers).IsEqual(1);
        AssertThat(Meta.BuyVigor(save)).OverrideFailureMessage("15 embers for the third level").IsFalse();
        AssertThat(save.Meta.Vigor).IsEqual(2);
        AssertThat(Meta.MaxHp(save)).IsEqual(Meta.BaseHp + 2);
    }

    [TestCase]
    public void Vigor_stops_at_its_top_level()
    {
        var save = new SaveData();
        save.Meta.Embers = 100;
        for (int i = 0; i < 5; i++)
            Meta.BuyVigor(save);
        AssertThat(save.Meta.Vigor).IsEqual(Meta.VigorMax);
        AssertThat(save.Meta.Embers).IsEqual(100 - 5 - 10 - 15);
    }
}
