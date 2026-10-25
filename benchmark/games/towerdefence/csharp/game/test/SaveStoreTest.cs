namespace Bramblegate.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading, writing and the move from version 1.</summary>
[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"bramblegate-{Guid.NewGuid():N}.json");
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
        AssertThat(data.Progress.Count).IsEqual(0);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Locale = "fr", Volume = 0.25 };
        Progress.Record(data, "meadow", 20, 20);
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(Progress.Stars(back, "meadow")).IsEqual(3);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(back.Volume).IsEqualApprox(0.25, 0.001);
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
    }

    [TestCase]
    public void A_damaged_save_gives_the_defaults()
    {
        File.WriteAllText(_path, "{ not json");
        AssertThat(new SaveStore(_path).Read().Progress.Count).IsEqual(0);
    }

    [TestCase]
    public void A_version_1_save_keeps_its_cleared_maps()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": ["meadow", "sunken"], "volume": 0.5}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.IsCleared(data, "meadow")).IsTrue();
        AssertThat(Progress.IsCleared(data, "sunken")).IsTrue();
        AssertThat(data.Volume).IsEqualApprox(0.5, 0.001);
    }

    [TestCase]
    public void A_disabled_store_writes_nothing()
    {
        var store = new SaveStore(_path) { Enabled = false };
        AssertThat(store.Write(new SaveData())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }
}
