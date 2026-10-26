namespace Cinderloop.Tests;

using System;
using System.Collections.Generic;
using System.IO;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden acceptance for the prototype-to-alpha milestone: two tracks a driver can finish, and a save that keeps the
/// best laps and the open tracks.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenTwoTracksTest
{
    private string _path = "";

    [BeforeTest]
    public void MakePath()
    {
        _path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cinderloop-two-tracks-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void RemoveFile()
    {
        File.Delete(_path);
        File.Delete(_path + ".tmp");
    }

    [TestCase]
    public void Hidden_two_tracks_a_driver_can_finish()
    {
        Tracks tracks = Tracks.FromFiles();
        foreach (int id in new[] { 1, 2 })
        {
            // A missing track has no road to race on: stop here rather than race on nothing.
            AssertThat(tracks.HasTrack(id)).OverrideFailureMessage($"track {id}").IsTrue();
            var race = new Race(tracks.Track(id), new List<AiDriver?> { new AiDriver() }, 60);
            while (race.FinishOrder.Count == 0 && race.Tick < 120 * 60)
                race.Step();
            AssertThat(race.FinishOrder).OverrideFailureMessage($"track {id} finished").ContainsExactly(0);
        }
        AssertThat(tracks.Row(2)!.Name).IsEqual("TRACK_2");
        AssertThat(TranslationServer.Translate("TRACK_2").ToString()).IsNotEqual("TRACK_2");
    }

    [TestCase]
    public void Hidden_the_save_keeps_best_laps_and_open_tracks()
    {
        var store = new SaveStore(_path);
        SaveData data = store.Read();
        AssertThat(data.Unlocked).IsEqual(1);
        data.Unlocked = 2;
        data.Best["2"] = 31250;
        AssertThat(store.Write(data)).IsTrue();
        SaveData back = new SaveStore(_path).Read();
        AssertThat(back.Unlocked).IsEqual(2);
        AssertThat(back.Best["2"]).IsEqual(31250);
    }
}
