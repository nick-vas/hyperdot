namespace Cinderloop.Tests;

using System;
using System.IO;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing, best laps and their ghosts.</summary>
[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"cinderloop-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
        File.Delete(_path + ".tmp");
    }

    [TestCase]
    public void No_save_gives_the_defaults()
    {
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Unlocked).IsEqual(1);
        AssertThat(data.Best.Count).IsEqual(0);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Unlocked = 3, Locale = "fr" };
        data.Best["1"] = 25480;
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(back.Unlocked).IsEqual(3);
        AssertThat(back.Best["1"]).IsEqual(25480);
        AssertThat(back.Locale).IsEqual("fr");
    }

    [TestCase]
    public void A_damaged_save_gives_the_defaults()
    {
        File.WriteAllText(_path, "{ not json");
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(1);
    }

    [TestCase]
    public void A_lap_is_kept_only_when_it_beats_the_best()
    {
        var data = new SaveData();
        var ghost = new Ghost(new CarState(Vector2.Zero, 0.0, 0.0));
        ghost.Record(1.0, 0.0);
        AssertThat(SaveStore.RecordLap(data, 2, 30000, ghost)).IsTrue();
        AssertThat(SaveStore.RecordLap(data, 2, 31000, null)).IsFalse();
        AssertThat(SaveStore.RecordLap(data, 2, 29500, ghost)).IsTrue();
        AssertThat(data.Best["2"]).IsEqual(29500);
        AssertThat(data.Ghosts.ContainsKey("2")).IsTrue();
    }

    [TestCase]
    public void A_saved_ghost_comes_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData();
        var ghost = new Ghost(new CarState(new Vector2(10.5f, -3.25f), 0.75, 120.0));
        for (int i = 0; i < 10; i++)
            ghost.Record(1.0, -0.37);
        SaveStore.RecordLap(data, 1, 9000, ghost);
        store.Write(data);
        Ghost back = Ghost.FromDict(store.Read().Ghosts["1"])!;
        AssertThat(back.Ticks()).IsEqual(10);
        AssertThat(back.Start.Position).IsEqual(new Vector2(10.5f, -3.25f));
        AssertThat(back.InputAt(9)).IsEqual(new Vector2(1f, -0.37f));
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }
}
