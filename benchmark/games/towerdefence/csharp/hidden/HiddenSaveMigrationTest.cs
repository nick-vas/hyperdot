namespace Bramblegate.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: version 1 saves (a list of maps cleared and the volume) load as cleared
/// maps, a save without a version is version 1, recording over a migrated save works, and version 2 saves load as they
/// were.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSaveMigrationTest
{
    private string _path = "";
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"bramblegate-hidden-migration-{Guid.NewGuid():N}.json");
        _catalog = Catalog.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_a_version_1_save_keeps_its_cleared_maps()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": ["meadow"], "volume": 0.4}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.IsCleared(data, "meadow")).IsTrue();
        AssertThat(Progress.IsCleared(data, "sunken")).IsFalse();
        AssertThat(Progress.IsUnlocked(data, _catalog, 2)).IsTrue();
        AssertThat(data.Volume).IsEqualApprox(0.4, 0.001);
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void Hidden_a_save_without_a_version_is_version_1()
    {
        File.WriteAllText(_path, """{"cleared": ["meadow", "sunken"]}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.IsCleared(data, "meadow")).IsTrue();
        AssertThat(Progress.IsCleared(data, "sunken")).IsTrue();
    }

    [TestCase]
    public void Hidden_a_migrated_save_records_and_writes_as_version_2()
    {
        File.WriteAllText(_path, """{"version": 1, "cleared": ["meadow"], "volume": 1.0}""");
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        Progress.Record(data, "meadow", 20, 20);
        Progress.Record(data, "sunken", 8, 20);
        AssertThat(store.Write(data)).IsTrue();
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat((int)raw["version"]!).IsEqual(2);
        SaveData back = store.Read();
        AssertThat(Progress.Stars(back, "meadow")).IsEqual(3);
        AssertThat(Progress.Stars(back, "sunken")).IsEqual(1);
    }

    [TestCase]
    public void Hidden_a_version_2_save_loads_as_it_was()
    {
        File.WriteAllText(_path, """{"version": 2, "progress": {"sunken": {"stars": 2, "lives": 12}}, "settings": {"volume": 0.5, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(Progress.Stars(data, "sunken")).IsEqual(2);
        AssertThat(data.Progress["sunken"].Lives).IsEqual(12);
        AssertThat(data.Volume).IsEqualApprox(0.5, 0.001);
    }
}
