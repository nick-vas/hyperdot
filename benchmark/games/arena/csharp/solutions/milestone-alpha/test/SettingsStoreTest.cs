namespace Glimmerpit.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>SettingsStore: reading and writing.</summary>
[TestSuite]
[RequireGodotRuntime]
public class SettingsStoreTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"glimmerpit-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    private static void AssertDefaults(SettingsData data)
    {
        AssertThat(data.Version).IsEqual(SettingsStore.Version);
        AssertThat(data.Volume).IsEqual(1.0);
        AssertThat(data.Locale).IsEqual("en");
        AssertThat(data.Played).IsEqual(0);
        AssertThat(data.Won).IsEqual(0);
    }

    [TestCase]
    public void No_file_gives_the_defaults()
    {
        AssertDefaults(new SettingsStore(_path).Read());
    }

    [TestCase]
    public void Settings_survive_a_write_and_a_read()
    {
        var store = new SettingsStore(_path);
        var data = new SettingsData { Volume = 0.4, Locale = "fr", Played = 3, Won = 1 };
        AssertThat(store.Write(data)).IsTrue();
        SettingsData back = store.Read();
        AssertThat(back.Volume).IsEqualApprox(0.4, 0.0001);
        AssertThat(back.Locale).IsEqual("fr");
        AssertThat(back.Played).IsEqual(3);
        AssertThat(back.Won).IsEqual(1);
    }

    [TestCase]
    public void A_damaged_file_gives_the_defaults()
    {
        File.WriteAllText(_path, "{ not json");
        AssertDefaults(new SettingsStore(_path).Read());
    }

    [TestCase]
    public void Writing_is_off_with_no_save()
    {
        var store = new SettingsStore(_path) { Enabled = false };
        AssertThat(store.Write(SettingsStore.Defaults())).IsFalse();
        AssertThat(File.Exists(_path)).IsFalse();
    }
}
