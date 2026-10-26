namespace Glimmerpit.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: settings files of version 1 ({"volume_db", "language"}, with or without
/// "version": 1) load with their volume and language, and version 2 files still load as they are.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSettingsMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"glimmerpit-hidden-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_version_1_decibels_become_a_linear_volume()
    {
        File.WriteAllText(_path, """{"version": 1, "volume_db": -6.0, "language": "fr"}""");
        SettingsData data = new SettingsStore(_path).Read();
        AssertThat(data.Volume).IsEqualApprox(0.501, 0.002);
        AssertThat(data.Locale).IsEqual("fr");
        AssertThat(data.Version).IsEqual(2);
    }

    [TestCase]
    public void Hidden_a_file_without_a_version_is_version_1()
    {
        File.WriteAllText(_path, """{"volume_db": -12.0, "language": "de"}""");
        SettingsData data = new SettingsStore(_path).Read();
        AssertThat(data.Volume).IsEqualApprox(0.251, 0.002);
        AssertThat(data.Locale).IsEqual("de");
    }

    [TestCase]
    public void Hidden_full_volume_stays_full()
    {
        File.WriteAllText(_path, """{"volume_db": 0.0, "language": "en"}""");
        AssertThat(new SettingsStore(_path).Read().Volume).IsEqualApprox(1.0, 0.001);
    }

    [TestCase]
    public void Hidden_a_migrated_file_is_written_as_version_2()
    {
        File.WriteAllText(_path, """{"volume_db": -6.0, "language": "fr"}""");
        var store = new SettingsStore(_path);
        SettingsData data = store.Read();
        data.Played = 2;
        store.Write(data);
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat((int)raw["version"]!.GetValue<double>()).IsEqual(2);
        SettingsData back = store.Read();
        AssertThat(back.Volume).IsEqualApprox(0.501, 0.002);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(back.Played).IsEqual(2);
    }

    [TestCase]
    public void Hidden_version_2_files_load_unchanged()
    {
        File.WriteAllText(_path, """{"version": 2, "volume": 0.3, "locale": "fr", "played": 4, "won": 1}""");
        SettingsData data = new SettingsStore(_path).Read();
        AssertThat(data.Volume).IsEqualApprox(0.3, 0.0001);
        AssertThat(data.Locale).IsEqual("fr");
        AssertThat(data.Played).IsEqual(4);
        AssertThat(data.Won).IsEqual(1);
    }
}
