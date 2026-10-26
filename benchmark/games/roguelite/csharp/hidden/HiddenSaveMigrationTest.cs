namespace Wickerdeep.Tests;

using System;
using System.IO;
using System.Text.Json.Nodes;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's migrate-save: a version 1 save (embers and the deepest floor) and one without a version
/// load into the current shape, a run banked over a migrated save adds to it, and a version 2 save still loads as written.
/// </summary>
[TestSuite]
public class HiddenSaveMigrationTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = Path.Combine(Path.GetTempPath(), $"wickerdeep-hidden-migration-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_version_1_keeps_its_embers_and_floor()
    {
        File.WriteAllText(_path, """{"version": 1, "embers": 23, "best": 3}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Meta.Embers).IsEqual(23);
        AssertThat(data.Meta.BestFloor).IsEqual(3);
        AssertThat(data.Meta.Vigor).IsEqual(0);
        AssertThat(data.Meta.Runs).IsEqual(0);
        AssertThat(data.Run).IsNull();
        AssertThat(data.Locale).IsEqual("en");
    }

    [TestCase]
    public void Hidden_a_save_without_a_version_is_version_1()
    {
        File.WriteAllText(_path, """{"embers": 9, "best": 2}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Meta.Embers).IsEqual(9);
        AssertThat(data.Meta.BestFloor).IsEqual(2);
    }

    [TestCase]
    public void Hidden_a_migrated_save_banks_and_writes_as_version_2()
    {
        File.WriteAllText(_path, """{"version": 1, "embers": 12, "best": 2}""");
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        AssertThat(Meta.BuyVigor(data)).IsTrue();
        Meta.Bank(data, 4, 1, true);
        store.Write(data);
        var raw = JsonNode.Parse(File.ReadAllText(_path))!.AsObject();
        AssertThat(raw["version"]!.GetValue<int>()).IsEqual(2);
        SaveData back = store.Read();
        AssertThat(back.Meta.Embers).IsEqual(11);
        AssertThat(back.Meta.Vigor).IsEqual(1);
        AssertThat(back.Meta.BestFloor).IsEqual(2);
    }

    [TestCase]
    public void Hidden_version_2_still_loads()
    {
        File.WriteAllText(_path, """{"version": 2, "meta": {"embers": 30, "vigor": 2, "best_floor": 4, "runs": 7}, "run": {"seed": 5, "floor": 2, "hp": 3, "max_hp": 7, "embers": 4}, "settings": {"volume": 0.5, "locale": "en"}}""");
        SaveData data = new SaveStore(_path).Read();
        AssertThat(data.Meta.Embers).IsEqual(30);
        AssertThat(data.Meta.Vigor).IsEqual(2);
        AssertThat(data.Meta.BestFloor).IsEqual(4);
        AssertThat(data.Meta.Runs).IsEqual(7);
        AssertThat(Run.FromDict(data.Run!).FloorNumber).IsEqual(2);
        AssertThat(Math.Abs(data.Volume - 0.5) < 0.001).IsTrue();
    }
}
