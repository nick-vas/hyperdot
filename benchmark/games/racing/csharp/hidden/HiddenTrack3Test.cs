namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the alpha's add-content: track 3, Caldera Hairpins, is a clean loop with its checkpoints in order and
/// hairpins, and a full-pace driver finishes it on the road in a fair time.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenTrack3Test
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    /// <summary>Track 3; a test without it stops here, as there is no road to check or race on.</summary>
    private Track Track3()
    {
        AssertThat(_tracks.HasTrack(3)).OverrideFailureMessage("no track 3").IsTrue();
        return _tracks.Track(3);
    }

    [TestCase]
    public void Hidden_track_3_is_named_and_listed()
    {
        Track3();
        TrackRow row = _tracks.Row(3)!;
        AssertThat(row.Name).IsEqual("TRACK_3");
        AssertThat(TranslationServer.Translate("TRACK_3").ToString()).IsEqual("Caldera Hairpins");
        AssertThat(row.Laps).IsEqual(2);
        AssertThat(row.Width).IsBetween(120.0, 200.0);
    }

    [TestCase]
    public void Hidden_its_checkpoints_go_round_in_order()
    {
        Track3();
        TrackRow row = _tracks.Row(3)!;
        List<int> checkpoints = row.Checkpoints;
        AssertThat(checkpoints.Count).IsGreaterEqual(6);
        for (int k = 1; k < checkpoints.Count; k++)
            AssertThat(checkpoints[k]).OverrideFailureMessage($"checkpoint {k} after {k - 1}").IsGreater(checkpoints[k - 1]);
        AssertThat(checkpoints[^1]).IsLess(row.Points.Count);
    }

    [TestCase]
    public void Hidden_the_road_never_runs_into_itself()
    {
        Track track = Track3();
        int n = track.PointCount();
        double clearance = double.PositiveInfinity;
        for (int i = 0; i < n; i++)
        {
            for (int j = i + 30; j < n - 30 + i; j++)
                clearance = System.Math.Min(clearance, track.Point(i).DistanceTo(track.Point(j)));
        }
        AssertThat(clearance).IsGreater(track.Width + 60.0);
    }

    [TestCase]
    public void Hidden_it_has_hairpins()
    {
        Track track = Track3();
        int dips = 0;
        bool inside = track.SpeedProfile[track.PointCount() - 1] < 250.0;
        for (int i = 0; i < track.PointCount(); i++)
        {
            bool slow = track.SpeedProfile[i] < 250.0;
            if (slow && !inside)
                dips += 1;
            inside = slow;
        }
        AssertThat(dips).OverrideFailureMessage("bends the AI takes under 250 px/s").IsGreaterEqual(2);
    }

    [TestCase]
    public void Hidden_a_full_pace_driver_finishes_it_on_the_road()
    {
        var race = new Race(Track3(), new List<AiDriver?> { new AiDriver() }, 60);
        int off = 0;
        while (race.FinishOrder.Count == 0 && race.Tick < 90 * 60)
        {
            race.Step();
            if (!race.Cars[0].OnRoad)
                off += 1;
        }
        AssertThat(race.FinishOrder).ContainsExactly(0);
        AssertThat(off).OverrideFailureMessage("ticks off the road").IsEqual(0);
        AssertThat(race.Tick / 60.0).OverrideFailureMessage("seconds for both laps").IsBetween(30.0, 70.0);
    }
}
