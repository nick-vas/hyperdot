namespace Cinderloop.Tests;

using System.Collections.Generic;
using System.Linq;
using GdUnit4;
using Godot;
using static GdUnit4.Assertions;

/// <summary>Race: the grid, the order of the finish, and a race that replays exactly from its grid and inputs.</summary>
[TestSuite]
[RequireGodotRuntime]
public class RaceTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    private static void Run(Race race, double seconds, Vector2 input)
    {
        int ticks = Maths.RoundI(seconds * race.Rate);
        for (int i = 0; i < ticks; i++)
            race.Step(input);
    }

    [TestCase]
    public void The_player_starts_at_the_back_of_the_grid()
    {
        var race = new Race(_tracks.Track(1), _tracks.DriversFor(3, 5), 60);
        AssertThat(race.Cars.Count).IsEqual(4);
        double line = race.Track.Lengths[race.Track.GatePoints[0]];
        var behind = new List<double>();
        foreach (Car car in race.Cars)
            behind.Add(Maths.FPosMod(line - race.Track.DistanceAlong(car.Position, car.Index), race.Track.Length()));
        AssertThat(behind.Max()).OverrideFailureMessage("the player's car is furthest from the line").IsEqual(behind[0]);
    }

    [TestCase]
    public void The_same_grid_and_inputs_drive_the_same_race()
    {
        var a = new Race(_tracks.Track(1), _tracks.DriversFor(3, 11), 60);
        var b = new Race(_tracks.Track(1), _tracks.DriversFor(3, 11), 60);
        Run(a, 8.0, new Vector2(1f, 0.13f));
        Run(b, 8.0, new Vector2(1f, 0.13f));
        for (int i = 0; i < a.Cars.Count; i++)
        {
            AssertThat(a.Cars[i].Position).OverrideFailureMessage($"car {i}").IsEqual(b.Cars[i].Position);
            AssertThat(a.Cars[i].Heading).OverrideFailureMessage($"car {i}").IsEqual(b.Cars[i].Heading);
        }
    }

    [TestCase]
    public void A_seed_shuffles_the_rivals_on_the_grid()
    {
        var orders = new HashSet<string>();
        for (int seed = 0; seed < 8; seed++)
            orders.Add(string.Join(",", _tracks.GridOrder(3, seed)));
        AssertThat(orders.Count).IsGreater(1);
    }

    [TestCase]
    public void The_cars_take_the_flag_in_order()
    {
        var race = new Race(_tracks.Track(1), _tracks.DriversFor(3, 5, true), 60);
        var places = new List<int>();
        race.CarFinished += (car, place) => places.Add(place);
        while (race.FinishOrder.Count < 4 && race.Tick < 90 * 60)
            race.Step();
        AssertThat(places).ContainsExactly(1, 2, 3, 4);
        AssertThat(race.FinishOrder[0]).OverrideFailureMessage("the bot beats the rivals").IsEqual(0);
    }

    [TestCase]
    public void Every_lap_of_the_player_is_recorded_for_its_ghost()
    {
        var race = new Race(_tracks.Track(1), _tracks.DriversFor(1, 5, true), 60);
        while (race.Trackers[0].Laps < 2 && race.Tick < 60 * 60)
            race.Step();
        AssertThat(race.BestGhost).IsNotNull();
        AssertThat(race.BestGhost!.Ticks()).IsEqual(race.Trackers[0].LapTimes.Min());
    }
}
