namespace Cinderloop.Tests;

using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>LapTracker: the start line arms it, the gates in order make a lap, and lap times are the ticks between the lines.</summary>
[TestSuite]
[RequireGodotRuntime]
public class LapTrackerTest
{
    private Track _track = null!;

    [BeforeTest]
    public void Load()
    {
        _track = Tracks.FromFiles().Track(1);
    }

    /// <summary>Moves a car across a gate, 20 pixels either side of it, at the given tick.</summary>
    private LapTracker.Crossing Cross(LapTracker tracker, int gate, int tick)
    {
        int i = _track.GatePoints[gate];
        Vector2 along = _track.Tangent(i) * 20f;
        return tracker.Update(_track, _track.Point(i) - along, _track.Point(i) + along, tick);
    }

    /// <summary>A whole lap from the line: every checkpoint in order, then the line, the last at endTick.</summary>
    private void Lap(LapTracker tracker, int startTick, int endTick)
    {
        int gates = _track.GateCount();
        for (int g = 1; g < gates; g++)
            Cross(tracker, g, startTick + (endTick - startTick) * g / gates);
        Cross(tracker, 0, endTick);
    }

    [TestCase]
    public void The_first_crossing_of_the_line_only_arms_the_tracker()
    {
        var tracker = new LapTracker();
        AssertThat(Cross(tracker, 0, 20)).IsEqual(LapTracker.Crossing.Gate);
        AssertThat(tracker.Armed).IsTrue();
        AssertThat(tracker.Laps).IsEqual(0);
        AssertThat(tracker.NextGate).IsEqual(1);
    }

    [TestCase]
    public void Every_checkpoint_in_order_then_the_line_is_a_lap()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 20);
        Lap(tracker, 20, 600);
        AssertThat(tracker.Laps).IsEqual(1);
        AssertThat(tracker.NextGate).IsEqual(1);
    }

    [TestCase]
    public void The_first_lap_is_timed_from_the_start()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 20);
        Lap(tracker, 20, 600);
        AssertThat(tracker.LastLap()).IsEqual(600);
    }

    [TestCase]
    public void A_lap_time_is_the_ticks_between_two_crossings_of_the_line()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 20);
        Lap(tracker, 20, 600);
        Lap(tracker, 600, 900);
        AssertThat(tracker.LapTimes).ContainsExactly(600, 300);
    }

    [TestCase]
    public void The_best_lap_is_the_fastest()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 20);
        Lap(tracker, 20, 600);
        Lap(tracker, 600, 900);
        Lap(tracker, 900, 1250);
        AssertThat(tracker.BestLap).IsEqual(300);
        AssertThat(tracker.Laps).IsEqual(3);
    }

    [TestCase]
    public void Crossing_the_line_again_without_the_checkpoints_is_no_lap()
    {
        var tracker = new LapTracker();
        Cross(tracker, 0, 20);
        AssertThat(Cross(tracker, 0, 80)).IsEqual(LapTracker.Crossing.None);
        AssertThat(tracker.Laps).IsEqual(0);
    }

    [TestCase]
    public void Gates_passed_counts_the_lap_in_progress()
    {
        var tracker = new LapTracker();
        AssertThat(tracker.GatesPassed(_track)).IsEqual(0);
        Cross(tracker, 0, 20);
        Cross(tracker, 1, 120);
        AssertThat(tracker.GatesPassed(_track)).IsEqual(2);
    }
}
