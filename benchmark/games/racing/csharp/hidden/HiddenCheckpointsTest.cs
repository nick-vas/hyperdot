namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's fix-bug: a lap counts only when every checkpoint was crossed in order. Skipping
/// one, over the grass or by moves fed straight to the tracker, never makes a lap; going back for it does.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenCheckpointsTest
{
    private Track _track = null!;

    [BeforeTest]
    public void Load()
    {
        _track = Tracks.FromFiles().Track(1);
    }

    private LapTracker.Crossing Cross(LapTracker tracker, int gate, int tick)
    {
        int i = _track.GatePoints[gate];
        Vector2 along = _track.Tangent(i) * 20f;
        return tracker.Update(_track, _track.Point(i) - along, _track.Point(i) + along, tick);
    }

    /// <summary>Moves the car along a polyline in steps of at most 12 pixels, from tick on; returns the laps made.</summary>
    private int Drive(LapTracker tracker, List<Vector2> points, int tick = 1)
    {
        for (int k = 0; k < points.Count - 1; k++)
        {
            Vector2 a = points[k];
            Vector2 b = points[k + 1];
            int steps = System.Math.Max((int)System.Math.Ceiling(a.DistanceTo(b) / 12.0), 1);
            for (int s = 0; s < steps; s++)
            {
                tracker.Update(_track, a.Lerp(b, (float)s / steps), a.Lerp(b, (float)(s + 1) / steps), tick);
                tick += 1;
            }
        }
        return tracker.Laps;
    }

    [TestCase]
    public void Hidden_every_gate_in_order_is_a_lap()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 1);
        for (int g = 1; g < _track.GateCount(); g++)
            Cross(tracker, g, 100 * g);
        AssertThat(Cross(tracker, 0, 900)).IsEqual(LapTracker.Crossing.Lap);
        AssertThat(tracker.Laps).IsEqual(1);
    }

    [TestCase]
    public void Hidden_a_skipped_gate_makes_no_lap()
    {
        for (int skipped = 1; skipped < _track.GateCount(); skipped++)
        {
            var tracker = new LapTracker();
            Cross(tracker, 0, 1);
            for (int g = 1; g < _track.GateCount(); g++)
            {
                if (g != skipped)
                    Cross(tracker, g, 100 * g);
            }
            Cross(tracker, 0, 900);
            AssertThat(tracker.Laps).OverrideFailureMessage($"gate {skipped} skipped").IsEqual(0);
        }
    }

    [TestCase]
    public void Hidden_going_back_for_a_skipped_gate_makes_the_lap()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 1);
        Cross(tracker, 1, 100);
        Cross(tracker, 3, 200);
        Cross(tracker, 2, 300);
        Cross(tracker, 3, 400);
        Cross(tracker, 0, 500);
        AssertThat(tracker.Laps).IsEqual(1);
        AssertThat(tracker.LastLap()).IsEqual(500);
    }

    [TestCase]
    public void Hidden_gates_out_of_order_make_no_lap()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 1);
        Cross(tracker, 1, 100);
        Cross(tracker, 3, 200);
        Cross(tracker, 2, 300);
        Cross(tracker, 0, 400);
        AssertThat(tracker.Laps).IsEqual(0);
    }

    [TestCase]
    public void Hidden_a_lap_driven_backwards_does_not_count()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 1);
        int tick = 2;
        foreach (int g in new[] { 3, 2, 1, 0, 3, 2, 1, 0 })
        {
            int i = _track.GatePoints[g];
            Vector2 along = _track.Tangent(i) * 20f;
            tracker.Update(_track, _track.Point(i) + along, _track.Point(i) - along, tick);
            tick += 50;
        }
        AssertThat(tracker.Laps).IsEqual(0);
    }

    [TestCase]
    public void Hidden_a_shortcut_across_the_infield_makes_no_lap()
    {
        var tracker = new LapTracker();
        Vector2 line = _track.Point(_track.GatePoints[0]);
        // Off the grid over the line, then straight up across the grass to the far straight, and round to the line.
        var path = new List<Vector2> { line + new Vector2(-200, 0), line + new Vector2(300, 0), new Vector2(0, -490) };
        int i = _track.Nearest(new Vector2(0, -490));
        while (Maths.PosMod(i, _track.PointCount()) != _track.GatePoints[0])
        {
            i += 1;
            path.Add(_track.Point(i));
        }
        path.Add(line + new Vector2(150, 0));
        AssertThat(Drive(tracker, path)).OverrideFailureMessage("the lap skipped the far gates").IsEqual(0);
        AssertThat(tracker.Armed).IsTrue();
    }

    [TestCase]
    public void Hidden_the_whole_lap_on_the_road_counts()
    {
        var tracker = new LapTracker();
        int start = _track.GatePoints[0];
        var path = new List<Vector2> { _track.Point(start - 3) };
        for (int k = 0; k < _track.PointCount() + 4; k++)
            path.Add(_track.Point(start - 2 + k));
        AssertThat(Drive(tracker, path)).IsEqual(1);
    }
}
