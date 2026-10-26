namespace Wickerdeep.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing, the run kept for Continue, and the move from version 1.</summary>
[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"wickerdeep-{Guid.NewGuid():N}.json");
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
        AssertThat(data.Meta.Embers).IsEqual(0);
        AssertThat(data.Run).IsNull();
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Locale = "fr" };
        Meta.Bank(data, 12, 3, true);
        AssertThat(Meta.BuyVigor(data)).IsTrue();
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(back.Meta.Embers).IsEqual(7);
        AssertThat(back.Meta.Vigor).IsEqual(1);
        AssertThat(back.Meta.BestFloor).IsEqual(3);
        AssertThat(back.Meta.Runs).IsEqual(1);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
    }

    [TestCase]
    public void The_run_in_progress_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData();
        var run = new Run(42, 6) { FloorNumber = 3, Hp = 4, Embers = 9 };
        data.Run = run.ToDict();
        store.Write(data);
        Run back = Run.FromDict(store.Read().Run!);
        AssertThat(back.Seed).IsEqual(42L);
        AssertThat(back.FloorNumber).IsEqual(3);
        AssertThat(back.Hp).IsEqual(4);
        AssertThat(back.MaxHp).IsEqual(6);
        AssertThat(back.Embers).IsEqual(9);
        AssertThat(back.FloorSeed()).IsEqual(run.FloorSeed());
    }

    [TestCase]
    public void A_version_1_save_keeps_its_embers_and_deepest_floor()
    {
        File.WriteAllText(_path, """{"version": 1, "embers": 23, "best": 3}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Meta.Embers).IsEqual(23);
        AssertThat(data.Meta.BestFloor).IsEqual(3);
        AssertThat(data.Meta.Vigor).IsEqual(0);
        AssertThat(data.Run).IsNull();
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "not json {");
        AssertThat(new SaveStore(_path).Read().Meta.Embers).IsEqual(0);
    }
}
