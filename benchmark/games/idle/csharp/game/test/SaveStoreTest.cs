namespace Duskhive.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing and the move from version 2.</summary>
[TestSuite]
[RequireGodotRuntime]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"duskhive-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void No_file_gives_the_defaults()
    {
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Economy.Count).IsEqual(0);
        AssertThat(data.SavedAt).IsEqual(0.0);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "{ not json");
        AssertThat(new SaveStore(_path).Read().Economy.Count).IsEqual(0);
    }

    [TestCase]
    public void A_save_comes_back_as_written()
    {
        var economy = new Economy(Catalog.FromFiles()) { Glow = 12345678901234567890.0, Embers = 3.0, Dawns = 2 };
        economy.SetCount("moon_lily", 7);
        economy.Upgrades.Add("warm_hands");
        var store = new SaveStore(_path);
        AssertThat(store.Write(new SaveData { Economy = economy.ToDict(), SavedAt = 1761000000.5, Volume = 0.5, Locale = "de" })).IsTrue();
        SaveData data = store.Read();
        Economy back = Economy.FromDict(economy.Catalog, data.Economy);
        AssertThat(back.Glow).OverrideFailureMessage("past 2^53, the same double").IsEqual(economy.Glow);
        AssertThat(back.Count("moon_lily")).IsEqual(7);
        AssertThat(back.Upgrades.Contains("warm_hands")).IsTrue();
        AssertThat(back.Embers).IsEqual(3.0);
        AssertThat(back.Dawns).IsEqual(2);
        AssertThat(data.SavedAt).IsEqual(1761000000.5);
        AssertThat(data.Locale).IsEqual("de");
    }

    [TestCase]
    public void A_version_2_save_keeps_its_embers()
    {
        File.WriteAllText(_path, """{"version": 2, "economy": {"glow": 50.0, "owned": {"wick_moth": 3}}, "embers": 4.0, "dawns": 2, "saved_at": 100.0}""");
        Economy back = Economy.FromDict(Catalog.FromFiles(), new SaveStore(_path).Read().Economy);
        AssertThat(back.Embers).IsEqual(4.0);
        AssertThat(back.Dawns).IsEqual(2);
        AssertThat(back.Count("wick_moth")).IsEqual(3);
    }

    [TestCase]
    public void Writing_off_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }
}
