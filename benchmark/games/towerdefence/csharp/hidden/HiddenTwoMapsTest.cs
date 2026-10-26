namespace Bramblegate.Tests;

using System;
using System.IO;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>Hidden acceptance for the prototype-to-alpha milestone: two maps of four waves, and the save of each map's best.</summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenTwoMapsTest
{
    private string _path = "";
    private Catalog _catalog = null!;

    [BeforeTest]
    public void Load()
    {
        _path = Path.Combine(Path.GetTempPath(), $"bramblegate-hidden-two-maps-{Guid.NewGuid():N}.json");
        _catalog = Catalog.FromFiles();
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
    }

    [TestCase]
    public void Hidden_two_maps_of_four_waves()
    {
        AssertThat(_catalog.MapCount).IsGreaterEqual(2);
        AssertThat(_catalog.MapAt(1)!.Id).IsEqual("meadow");
        AssertThat(_catalog.MapAt(2)!.Id).IsEqual("sunken");
        AssertThat(_catalog.WavesFor("meadow").Count).IsEqual(4);
        AssertThat(_catalog.WavesFor("sunken").Count).IsEqual(4);
        AssertThat(PathMap.FromRows(_catalog.MapAt(2)!.Rows).Route).IsNotEmpty();
    }

    [TestCase]
    public void Hidden_stars_are_saved_and_open_the_next_map()
    {
        var store = new SaveStore(_path);
        SaveData save = store.Read();
        AssertThat(Progress.IsUnlocked(save, _catalog, 2)).IsFalse();
        Progress.Record(save, "meadow", 20, 20);
        AssertThat(store.Write(save)).IsTrue();
        SaveData back = store.Read();
        AssertThat(Progress.Stars(back, "meadow")).IsEqual(3);
        AssertThat(Progress.IsUnlocked(back, _catalog, 2)).IsTrue();
        Progress.Record(back, "meadow", 9, 20);
        AssertThat(Progress.Stars(back, "meadow")).OverrideFailureMessage("the best result is kept").IsEqual(3);
        Progress.Record(back, "sunken", 10, 20);
        AssertThat(Progress.Stars(back, "sunken")).IsEqual(2);
        Progress.Record(back, "sunken", 9, 20);
        AssertThat(Progress.Stars(back, "sunken")).IsEqual(2);
    }
}
