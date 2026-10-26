namespace Wickerdeep.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's fix-bug: what a run brings home joins the embers already banked, after a death as after
/// a victory, and survives the save.
/// </summary>
[TestSuite]
public class HiddenBankTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"wickerdeep-hidden-bank-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_deaths_and_victories_add_to_the_bank()
    {
        var save = new SaveData();
        Meta.Bank(save, 6, 3, false);
        AssertThat(save.Meta.Embers).IsEqual(3);
        Meta.Bank(save, 5, 1, false);
        AssertThat(save.Meta.Embers).IsEqual(5);
        Meta.Bank(save, 9, 2, true);
        AssertThat(save.Meta.Embers).IsEqual(14);
        Meta.Bank(save, 1, 1, false);
        AssertThat(save.Meta.Embers).OverrideFailureMessage("half of one is nothing").IsEqual(14);
        AssertThat(save.Meta.BestFloor).IsEqual(3);
        AssertThat(save.Meta.Runs).IsEqual(4);
    }

    [TestCase]
    public void Hidden_vigor_and_the_bank_survive_runs_and_the_save()
    {
        var store = new SaveStore(_path);
        var save = new SaveData();
        Meta.Bank(save, 8, 2, true);
        AssertThat(Meta.BuyVigor(save)).IsTrue();
        Meta.Bank(save, 4, 2, false);
        store.Write(save);
        SaveData back = store.Read();
        AssertThat(back.Meta.Embers).IsEqual(5);
        AssertThat(back.Meta.Vigor).IsEqual(1);
        Meta.Bank(back, 10, 4, true);
        AssertThat(back.Meta.Embers).IsEqual(15);
        AssertThat(Meta.BuyVigor(back)).IsTrue();
        AssertThat(back.Meta.Embers).IsEqual(5);
    }
}
