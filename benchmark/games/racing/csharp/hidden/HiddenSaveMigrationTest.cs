namespace Cinderloop.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: a version 1 save (best laps in seconds) loads with its laps in
/// milliseconds and its tracks open, a file without a version is version 1, a version 2 save is as it was, and saving
/// a migrated save writes version 2.
/// </summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"cinderloop-migration-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
        File.Delete(_path + ".tmp");
    }

    [TestCase]
    public void Hidden_version_1_best_laps_come_back_in_milliseconds()
    {
        File.WriteAllText(_path, "{\"version\": 1, \"best\": {\"1\": 25.481, \"2\": 30.0}}");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Best["1"]).IsEqual(25481);
        AssertThat(data.Best["2"]).IsEqual(30000);
    }

    [TestCase]
    public void Hidden_version_1_tracks_stay_open()
    {
        File.WriteAllText(_path, "{\"version\": 1, \"best\": {\"1\": 25.5}}");
        AssertThat(new SaveStore(_path).Read().Unlocked).IsEqual(2);
        File.WriteAllText(_path, "{\"version\": 1, \"best\": {\"1\": 25.5, \"2\": 31.25}}");
        AssertThat(new SaveStore(_path).Read().Unlocked).IsGreaterEqual(3);
    }

    [TestCase]
    public void Hidden_a_save_without_a_version_is_version_1()
    {
        File.WriteAllText(_path, "{\"best\": {\"1\": 26.0}}");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Best["1"]).IsEqual(26000);
        AssertThat(data.Unlocked).IsEqual(2);
    }

    [TestCase]
    public void Hidden_a_version_2_save_is_as_it_was()
    {
        File.WriteAllText(_path, "{\"version\": 2, \"unlocked\": 2, \"best\": {\"1\": 25481}, \"ghosts\": {}, \"settings\": {\"volume\": 0.5, \"locale\": \"en\"}, \"controls\": {\"brake\": \"K\"}}");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Unlocked).IsEqual(2);
        AssertThat(data.Best["1"]).IsEqual(25481);
        AssertThat(data.Volume).IsEqualApprox(0.5, 0.001);
        AssertThat(data.Controls.TryGetValue("brake", out string? key) ? key : null).IsEqual("K");
    }

    [TestCase]
    public void Hidden_a_migrated_save_is_written_as_version_2()
    {
        File.WriteAllText(_path, "{\"version\": 1, \"best\": {\"2\": 33.5}}");
        var store = new SaveStore(_path);
        store.Write(store.Read());
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat(raw["version"]!.GetValue<int>()).IsEqual(2);
        AssertThat(raw["best"]!["2"]!.GetValue<int>()).IsEqual(33500);
        AssertThat(new SaveStore(_path).Read().Best["2"]).IsEqual(33500);
    }
}
