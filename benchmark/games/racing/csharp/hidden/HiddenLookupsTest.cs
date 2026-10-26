namespace Cinderloop.Tests;

using System;
using System.Collections.Generic;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-performance: finding the track segment under each car costs a few segment checks a
/// tick, however many rivals race, and finds the same segment a search of the whole loop finds, also for a car that
/// left the road or was put somewhere new.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenLookupsTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    /// <summary>The nearest segment by looking at all of them, without touching the track's counter.</summary>
    private static int NearestEverywhere(Track track, Vector2 at)
    {
        int best = 0;
        double bestDistance = double.PositiveInfinity;
        for (int i = 0; i < track.PointCount(); i++)
        {
            double d = at.DistanceSquaredTo(Geometry2D.GetClosestPointToSegment(at, track.Point(i), track.Point(i + 1)));
            if (d < bestDistance)
            {
                bestDistance = d;
                best = i;
            }
        }
        return best;
    }

    private static bool SameSegment(Track track, Vector2 at, int found, int expected)
    {
        if (found == expected)
            return true;
        float a = at.DistanceTo(Geometry2D.GetClosestPointToSegment(at, track.Point(found), track.Point(found + 1)));
        float b = at.DistanceTo(Geometry2D.GetClosestPointToSegment(at, track.Point(expected), track.Point(expected + 1)));
        return Math.Abs(a - b) < 0.001;
    }

    [TestCase]
    public void Hidden_a_full_grid_costs_a_few_checks_a_car_a_tick()
    {
        var race = new Race(_tracks.Track(3), _tracks.DriversFor(11, 5, true), 60);
        race.Track.Lookups = 0;
        for (int i = 0; i < 600; i++)
            race.Step();
        double perCarTick = race.Track.Lookups / (double)(600 * race.Cars.Count);
        AssertThat(perCarTick).OverrideFailureMessage($"segment checks per car per tick (the loop has {race.Track.PointCount()})").IsLess(24.0);
    }

    [TestCase]
    public void Hidden_every_car_is_on_the_segment_a_full_search_finds()
    {
        var race = new Race(_tracks.Track(2), _tracks.DriversFor(7, 3, true), 60);
        int wrong = 0;
        for (int i = 0; i < 900; i++)
        {
            race.Step();
            foreach (Car car in race.Cars)
            {
                if (!SameSegment(race.Track, car.Position, car.Index, NearestEverywhere(race.Track, car.Position)))
                    wrong += 1;
            }
        }
        AssertThat(wrong).IsEqual(0);
    }

    [TestCase]
    public void Hidden_a_car_off_the_road_or_moved_is_found_again()
    {
        var race = new Race(_tracks.Track(1), new List<AiDriver?> { null }, 60);
        for (int i = 0; i < 60; i++)
            race.Step(new Vector2(1f, 0f));
        // Straight across the grass infield to the far straight, a few pixels a tick, then dropped at the far end.
        Car car = race.Cars[0];
        var spots = new List<Vector2>();
        for (int k = 0; k < 60; k++)
            spots.Add(car.Position.Lerp(new Vector2(0, -480), (k + 1) / 60f));
        spots.Add(new Vector2(-1250, 0));
        spots.Add(new Vector2(900, 420));
        foreach (Vector2 spot in spots)
        {
            car.Position = spot;
            car.Speed = 0.0;
            race.Step(Vector2.Zero);
            AssertThat(SameSegment(race.Track, car.Position, car.Index, NearestEverywhere(race.Track, car.Position))).OverrideFailureMessage($"at {car.Position}").IsTrue();
        }
    }

    [TestCase]
    public void Hidden_a_ghost_still_replays_its_lap()
    {
        var race = new Race(_tracks.Track(1), new List<AiDriver?> { new AiDriver() }, 60);
        var path = new List<Vector2>();
        while (race.Trackers[0].Laps < 1)
        {
            race.Step();
            path.Add(race.Cars[0].Position);
        }
        List<Vector2> replayed = race.BestGhost!.Replay(race.Track);
        AssertThat(replayed.Count).IsEqual(path.Count);
        AssertThat(replayed[^1].DistanceTo(path[^1])).IsEqualApprox(0f, 0.01f);
    }
}
