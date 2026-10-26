namespace Bramblegate.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: recording a cleared map keeps every other map's result, and a worse replay keeps
/// the best one.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenProgressTest
{
    private string _path = "";
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"bramblegate-hidden-progress-{Guid.NewGuid():N}.json");
        _catalog = Catalog.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_clearing_a_map_keeps_the_others()
    {
        var save = new SaveData();
        Progress.Record(save, "meadow", 20, 20);
        Progress.Record(save, "sunken", 12, 20);
        Progress.Record(save, "briar", 3, 20);
        AssertThat(Progress.Stars(save, "meadow")).IsEqual(3);
        AssertThat(Progress.Stars(save, "sunken")).IsEqual(2);
        AssertThat(Progress.Stars(save, "briar")).IsEqual(1);
        AssertThat(Progress.IsUnlocked(save, _catalog, 2)).IsTrue();
        AssertThat(Progress.IsUnlocked(save, _catalog, 3)).IsTrue();
        AssertThat(Progress.TotalStars(save)).IsEqual(6);
    }

    [TestCase]
    public void Hidden_a_worse_replay_keeps_the_best()
    {
        var save = new SaveData();
        Progress.Record(save, "meadow", 20, 20);
        Progress.Record(save, "sunken", 15, 20);
        Progress.Record(save, "meadow", 4, 20);
        AssertThat(Progress.Stars(save, "meadow")).IsEqual(3);
        AssertThat(save.Progress["meadow"].Lives).IsEqual(20);
        Progress.Record(save, "sunken", 18, 20);
        AssertThat(save.Progress["sunken"].Lives).OverrideFailureMessage("more seeds kept at the same stars is better").IsEqual(18);
    }

    [TestCase]
    public void Hidden_the_save_keeps_them_all()
    {
        var store = new SaveStore(_path);
        SaveData save = store.Read();
        Progress.Record(save, "meadow", 20, 20);
        store.Write(save);
        save = store.Read();
        Progress.Record(save, "sunken", 10, 20);
        store.Write(save);
        SaveData back = store.Read();
        AssertThat(Progress.IsCleared(back, "meadow")).IsTrue();
        AssertThat(Progress.IsCleared(back, "sunken")).IsTrue();
    }
}
