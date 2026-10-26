namespace Duskhive.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: a version 2 save, with the embers and dawns beside the economy, keeps them
/// (and everything else) when it loads, a file without a version is read the same way, and version 3 files are
/// untouched.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenSaveMigrationTest
{
    private const string V2 = """{"version": 2, "economy": {"glow": 123456789012345678901.0, "run_earned": 2e21, "total_earned": 5e21, "owned": {"wick_moth": 40, "moon_lily": 3}, "upgrades": ["twin_wicks"]}, "embers": 37.0, "dawns": 5, "saved_at": 1760000000.0, "settings": {"volume": 0.4, "locale": "en"}}""";

    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"duskhive-hidden-migration-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    private SaveData Load(string text)
    {
        File.WriteAllText(_path, text);
        return new SaveStore(_path).Read();
    }

    [TestCase]
    public void Hidden_version_2_keeps_its_embers_and_dawns()
    {
        SaveData data = Load(V2);
        Economy economy = Economy.FromDict(Catalog.FromFiles(), data.Economy);
        AssertThat(economy.Embers).IsEqual(37.0);
        AssertThat(economy.Dawns).IsEqual(5);
        AssertThat(economy.EmberMultiplier()).IsEqualApprox(4.7, 1e-9);
    }

    [TestCase]
    public void Hidden_version_2_keeps_everything_else()
    {
        SaveData data = Load(V2);
        Economy economy = Economy.FromDict(Catalog.FromFiles(), data.Economy);
        AssertThat(economy.Glow).IsEqual(123456789012345678901.0);
        AssertThat(economy.TotalEarned).IsEqual(5e21);
        AssertThat(economy.Count("wick_moth")).IsEqual(40);
        AssertThat(economy.Count("moon_lily")).IsEqual(3);
        AssertThat(economy.Upgrades.Contains("twin_wicks")).IsTrue();
        AssertThat(data.SavedAt).IsEqual(1760000000.0);
        AssertThat(data.Volume).IsEqualApprox(0.4, 1e-9);
    }

    [TestCase]
    public void Hidden_a_file_without_a_version_is_version_2()
    {
        SaveData data = Load("""{"economy": {"glow": 5.0}, "embers": 2.0, "dawns": 1}""");
        Economy economy = Economy.FromDict(Catalog.FromFiles(), data.Economy);
        AssertThat(economy.Embers).IsEqual(2.0);
        AssertThat(economy.Glow).IsEqual(5.0);
    }

    [TestCase]
    public void Hidden_a_migrated_save_is_written_as_version_3()
    {
        var store = new SaveStore(_path);
        SaveData data = Load(V2);
        AssertThat(store.Write(data)).IsTrue();
        var raw = (JsonObject)JsonNode.Parse(File.ReadAllText(_path))!;
        AssertThat(JsonData.Int(raw["version"], 0)).IsEqual(3);
        AssertThat(JsonData.Number(raw["economy"]?["prestige"]?["embers"], -1.0)).IsEqual(37.0);
        Economy again = Economy.FromDict(Catalog.FromFiles(), store.Read().Economy);
        AssertThat(again.Embers).IsEqual(37.0);
        AssertThat(again.Dawns).IsEqual(5);
    }

    [TestCase]
    public void Hidden_version_3_is_untouched()
    {
        var economy = new Economy(Catalog.FromFiles()) { Embers = 12.0, Dawns = 3, Glow = 77.0 };
        new SaveStore(_path).Write(new SaveData { Economy = economy.ToDict(), SavedAt = 1.0 });
        Economy back = Economy.FromDict(economy.Catalog, new SaveStore(_path).Read().Economy);
        AssertThat(back.Embers).IsEqual(12.0);
        AssertThat(back.Dawns).IsEqual(3);
        AssertThat(back.Glow).IsEqual(77.0);
    }
}
