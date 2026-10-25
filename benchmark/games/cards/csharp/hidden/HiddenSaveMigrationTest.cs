namespace Lanternfen.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: version 1 saves (a list of rivals beaten) load as beaten rivals, a save
/// without a version is version 1, recording over a migrated save works, and version 2 saves load as they were.
/// </summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"lanternfen-hidden-migration-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_a_version_1_save_keeps_its_beaten_rivals()
    {
        File.WriteAllText(_path, """{"version": 1, "beaten": [1, 2]}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Ladder.Wins(data, 1)).IsEqual(1);
        AssertThat(Ladder.Wins(data, 2)).IsEqual(1);
        AssertThat(Ladder.Losses(data, 1)).IsEqual(0);
        AssertThat(Ladder.IsUnlocked(data, 3)).IsTrue();
        AssertThat(Ladder.IsUnlocked(data, 4)).IsFalse();
        AssertThat(data.Duel).IsNull();
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void Hidden_a_save_without_a_version_is_version_1()
    {
        File.WriteAllText(_path, """{"beaten": [1]}""");
        AssertThat(Ladder.IsBeaten(new SaveStore(_path).Read(), 1)).IsTrue();
    }

    [TestCase]
    public void Hidden_a_migrated_save_records_and_writes_as_version_2()
    {
        File.WriteAllText(_path, """{"version": 1, "beaten": [1]}""");
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        Ladder.Record(data, 1, false);
        Ladder.Record(data, 2, true);
        AssertThat(store.Write(data)).IsTrue();
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat(raw["version"]!.GetValue<int>()).IsEqual(2);
        SaveData back = store.Read();
        AssertThat(Ladder.Wins(back, 1)).IsEqual(1);
        AssertThat(Ladder.Losses(back, 1)).IsEqual(1);
        AssertThat(Ladder.Wins(back, 2)).IsEqual(1);
    }

    [TestCase]
    public void Hidden_a_version_2_save_loads_as_it_was()
    {
        File.WriteAllText(_path, """{"version": 2, "record": {"3": {"wins": 2, "losses": 1}}, "duel": {"turn": 5}, "settings": {"volume": 0.5, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Ladder.Wins(data, 3)).IsEqual(2);
        AssertThat(Ladder.Losses(data, 3)).IsEqual(1);
        AssertThat(data.Duel!["turn"]!.GetValue<int>()).IsEqual(5);
        AssertThat(data.Volume).IsEqualApprox(0.5, 0.001);
    }
}
