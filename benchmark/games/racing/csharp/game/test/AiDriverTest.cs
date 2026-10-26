namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>AiDriver: alone on each track it finishes its laps without leaving the road, and a slower pace is slower.</summary>
[TestSuite]
[RequireGodotRuntime]
public class AiDriverTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    private Race Alone(int trackId, double pace) =>
        new(_tracks.Track(trackId), new List<AiDriver?> { new AiDriver(pace) }, Engine.PhysicsTicksPerSecond);

    [TestCase]
    public void The_driver_finishes_every_track_on_the_road()
    {
        foreach (TrackRow row in _tracks.Rows)
        {
            Race race = Alone(row.Id, 1.0);
            int off = 0;
            while (race.FinishOrder.Count == 0 && race.Tick < 120 * race.Rate)
            {
                race.Step();
                if (!race.Cars[0].OnRoad)
                    off += 1;
            }
            AssertThat(race.FinishOrder).OverrideFailureMessage($"track {row.Id} finished").ContainsExactly(0);
            AssertThat(off).OverrideFailureMessage($"track {row.Id}: ticks off the road").IsEqual(0);
        }
    }

    [TestCase]
    public void A_slower_pace_takes_longer()
    {
        Race fast = Alone(1, 1.0);
        Race slow = Alone(1, 0.85);
        while (fast.FinishOrder.Count == 0 && fast.Tick < 60 * fast.Rate)
            fast.Step();
        while (slow.FinishOrder.Count == 0 && slow.Tick < 60 * slow.Rate)
            slow.Step();
        AssertThat(slow.Trackers[0].BestLap).IsGreater(fast.Trackers[0].BestLap);
    }

    [TestCase]
    public void The_driver_brakes_before_the_tightest_bend()
    {
        Track? track = null;
        int slowest = 0;
        foreach (TrackRow row in _tracks.Rows)
        {
            Track t = Track.FromRow(row);
            for (int i = 0; i < t.PointCount(); i++)
            {
                if (track == null || t.SpeedProfile[i] < track.SpeedProfile[slowest])
                {
                    track = t;
                    slowest = i;
                }
            }
        }
        var car = new Car { Index = Maths.PosMod(slowest - 8, track!.PointCount()) };
        car.Position = track.Point(car.Index);
        car.Heading = track.Tangent(car.Index).Angle();
        car.Speed = Car.Accel / Car.Drag;
        AssertThat(new AiDriver().Decide(car, track).X).IsLess(0f);
    }
}
