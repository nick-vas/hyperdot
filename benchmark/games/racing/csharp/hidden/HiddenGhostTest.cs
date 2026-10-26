namespace Cinderloop.Tests;

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the beta's fix-bug: a ghost drives exactly the lap it recorded, tick by tick, after being saved and
/// loaded, for a driver with analog throttle and steering (a gamepad, or the AI), on the opening lap and a flying one.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenGhostTest
{
    private Tracks _tracks = null!;
    private string _path = "";

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
        _path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cinderloop-ghost-{Guid.NewGuid():N}.json");
    }

    [AfterTest]
    public void CleanUp()
    {
        File.Delete(_path);
        File.Delete(_path + ".tmp");
    }

    /// <summary>Drives laps with an analog driver as the player's input; returns each lap's positions, tick by tick.</summary>
    private static List<List<Vector2>> Drive(Race race, int laps)
    {
        var brain = new AiDriver(0.937, 7.5);
        var lapsDriven = new List<List<Vector2>> { new() };
        while (race.Trackers[0].Laps < laps && race.Tick < 120 * race.Rate)
        {
            int done = race.Trackers[0].Laps;
            race.Step(brain.Decide(race.Cars[0], race.Track));
            lapsDriven[^1].Add(race.Cars[0].Position);
            if (race.Trackers[0].Laps > done)
                lapsDriven.Add(new List<Vector2>());
        }
        return lapsDriven;
    }

    private Ghost RoundTrip(Ghost ghost)
    {
        var store = new SaveStore(_path);
        var data = new SaveData();
        SaveStore.RecordLap(data, 2, 1, ghost);
        store.Write(data);
        return Ghost.FromDict(store.Read().Ghosts["2"])!;
    }

    private static double WorstGap(List<Vector2> driven, List<Vector2> replayed)
    {
        double worst = 0.0;
        for (int t = 0; t < Math.Min(driven.Count, replayed.Count); t++)
            worst = Math.Max(worst, driven[t].DistanceTo(replayed[t]));
        return worst;
    }

    [TestCase]
    public void Hidden_the_opening_lap_replays_exactly()
    {
        var race = new Race(_tracks.Track(2), new List<AiDriver?> { null }, 60);
        Ghost first = race.Ghost;
        List<List<Vector2>> laps = Drive(race, 1);
        List<Vector2> replayed = RoundTrip(first).Replay(race.Track);
        AssertThat(replayed.Count).OverrideFailureMessage("as many ticks as the lap").IsEqual(laps[0].Count);
        AssertThat(WorstGap(laps[0], replayed)).OverrideFailureMessage("pixels apart at worst").IsLess(0.01);
    }

    [TestCase]
    public void Hidden_the_best_flying_lap_replays_exactly()
    {
        var race = new Race(_tracks.Track(2), new List<AiDriver?> { null }, 60);
        List<List<Vector2>> laps = Drive(race, 2);
        AssertThat(race.BestGhost!.Ticks()).IsEqual(race.Trackers[0].LapTimes.Min());
        int best = race.Trackers[0].LapTimes[0] <= race.Trackers[0].LapTimes[1] ? 0 : 1;
        List<Vector2> replayed = RoundTrip(race.BestGhost).Replay(race.Track);
        AssertThat(replayed.Count).IsEqual(laps[best].Count);
        AssertThat(WorstGap(laps[best], replayed)).OverrideFailureMessage("pixels apart at worst").IsLess(0.01);
    }

    [TestCase]
    public void Hidden_the_replay_crosses_the_line_on_the_lap_time()
    {
        var race = new Race(_tracks.Track(2), new List<AiDriver?> { null }, 60);
        Drive(race, 2);
        Ghost ghost = RoundTrip(race.BestGhost!);
        var tracker = new LapTracker { Armed = true };
        Car car = ghost.StartCar();
        car.Index = race.Track.Nearest(car.Position);
        int crossedAt = -1;
        for (int t = 0; t < ghost.Ticks(); t++)
        {
            Vector2 from = car.Position;
            ghost.Drive(car, t, race.Track);
            if (tracker.Update(race.Track, from, car.Position, t + 1) == LapTracker.Crossing.Lap && crossedAt < 0)
                crossedAt = t + 1;
        }
        AssertThat(crossedAt).IsEqual(race.Trackers[0].BestLap);
    }
}
