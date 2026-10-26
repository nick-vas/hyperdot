namespace Cinderloop.Tests;

using System.Collections.Generic;
using GdUnit4;
using static GdUnit4.Assertions;

/// <summary>
/// Hidden check for the prototype's add-feature: Race.Standings() and Race.PositionOf() rank the cars by the flag,
/// then laps, then gates passed in the lap, then the distance left to the next gate, level cars by index.
/// </summary>
[TestSuite]
[RequireGodotRuntime]
public class HiddenStandingsTest
{
    private Tracks _tracks = null!;

    [BeforeTest]
    public void Load()
    {
        _tracks = Tracks.FromFiles();
    }

    private Race MakeRace(int cars = 4) => new(_tracks.Track(1), _tracks.DriversFor(cars - 1, 9), 60);

    [TestCase]
    public void Hidden_the_grid_order_is_the_order_on_the_road()
    {
        Race race = MakeRace();
        // Car 0 starts at the back; the others in grid order, front row first.
        AssertThat(race.Standings()).ContainsExactly(1, 2, 3, 0);
        for (int i = 0; i < 4; i++)
            AssertThat(race.PositionOf(i)).IsEqual(race.Standings().IndexOf(i) + 1);
    }

    [TestCase]
    public void Hidden_more_laps_lead()
    {
        Race race = MakeRace();
        foreach (LapTracker t in race.Trackers)
        {
            t.Armed = true;
            t.NextGate = 2;
        }
        race.Trackers[3].Laps = 1;
        race.Trackers[0].Laps = 2;
        AssertThat(race.Standings().GetRange(0, 2)).ContainsExactly(0, 3);
    }

    [TestCase]
    public void Hidden_more_gates_in_the_lap_lead()
    {
        Race race = MakeRace();
        foreach (LapTracker t in race.Trackers)
            t.Armed = true;
        race.Trackers[2].NextGate = 3;
        race.Trackers[0].NextGate = 0;
        race.Trackers[1].NextGate = 1;
        race.Trackers[3].NextGate = 2;
        AssertThat(race.Standings()).ContainsExactly(0, 2, 3, 1);
    }

    [TestCase]
    public void Hidden_the_closer_to_the_next_gate_leads()
    {
        Race race = MakeRace(3);
        Track track = race.Track;
        for (int i = 0; i < 3; i++)
        {
            race.Trackers[i].Armed = true;
            race.Trackers[i].NextGate = 1;
        }
        int gate = track.GatePoints[1];
        for (int i = 0; i < 3; i++)
        {
            race.Cars[i].Position = track.Point(gate - 3 - 4 * i);
            race.Cars[i].Index = track.Nearest(race.Cars[i].Position);
        }
        AssertThat(race.Standings()).ContainsExactly(0, 1, 2);
        race.Cars[2].Position = track.Point(gate - 1);
        race.Cars[2].Index = track.Nearest(race.Cars[2].Position);
        AssertThat(race.PositionOf(2)).IsEqual(1);
    }

    [TestCase]
    public void Hidden_level_cars_go_by_index()
    {
        Race race = MakeRace(3);
        for (int i = 0; i < 3; i++)
        {
            race.Cars[i].Position = race.Cars[0].Position;
            race.Cars[i].Index = race.Cars[0].Index;
        }
        AssertThat(race.Standings()).ContainsExactly(0, 1, 2);
    }

    [TestCase]
    public void Hidden_the_flag_comes_first_in_its_order()
    {
        Race race = MakeRace();
        race.Trackers[1].Laps = 9;
        race.FinishOrder = new List<int> { 3, 0 };
        AssertThat(race.Standings().GetRange(0, 2)).ContainsExactly(3, 0);
        AssertThat(race.PositionOf(1)).IsEqual(3);
    }

    [TestCase]
    public void Hidden_a_real_race_ends_in_the_finish_order()
    {
        var race = new Race(_tracks.Track(1), _tracks.DriversFor(3, 9, true), 60);
        while (race.FinishOrder.Count < 4 && race.Tick < 120 * 60)
            race.Step();
        AssertThat(race.Standings()).ContainsExactly(race.FinishOrder);
    }
}
