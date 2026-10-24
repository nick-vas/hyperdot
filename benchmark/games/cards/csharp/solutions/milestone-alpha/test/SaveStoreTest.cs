namespace Lanternfen.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SaveStore: reading and writing.</summary>
[TestSuite]
public class SaveStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"lanternfen-{Guid.NewGuid():N}.json");
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
        AssertThat(data.Record.Count).IsEqual(0);
        AssertThat(data.Duel).IsNull();
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void What_is_written_reads_back()
    {
        var store = new SaveStore(_path);
        var data = new SaveData { Locale = "fr" };
        Ladder.Record(data, 1, true);
        Ladder.Record(data, 2, false);
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = store.Read();
        AssertThat(Ladder.Wins(back, 1)).IsEqual(1);
        AssertThat(Ladder.Losses(back, 2)).IsEqual(1);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(File.ReadAllText(_path)).Contains("\"version\": 2");
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
        AssertThat(new SaveStore(_path).Read().Record.Count).IsEqual(0);
    }
}
